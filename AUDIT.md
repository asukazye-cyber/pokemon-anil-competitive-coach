# AUDIT — Coach Engine 2.0

Audit and verification record for the Añil competitive coach rebuild.
Written per AGENT_PROMPT.md: audit first, claims only where verified, every
unsupported mechanic reported explicitly.

---

## 1. Baseline findings (repository as supplied)

| Item | Finding |
|---|---|
| `baseline/Scripts.rxdata` | 616 script entries; byte-identical round-trip verified with `tools/rxdata.py` (Marshal 4.8, zlib-deflated code strings, IVAR-UTF-8 names). Never modified. |
| Script index vs id | Section index in the rxdata ≠ script id. Last id is 20260920; the new Engine 2.0 section takes 20260921. |
| Old Coach stack | v5–v18 live inside `160_0158_Battle_CommandPhase.rb` (methods + `alias competitive_coach_vN_previous_recommendation` chains). v19–v27 are separate sections 609–615, each re-aliasing `competitive_coach_recommendation`. HUD reader in section 483 (`competitive_coach_show`) consumes `{best:, alternative:, confidence_dots:, warning:}`. |
| `PBDebug.logonerr` | Rescues ALL exceptions in `pbCommandPhase`/`pbAttackPhase`/`pbEndOfRoundPhase`/`pbUseMove` loops and forwards to `pbPrintException`. A broken `pbPrintException` silently masks engine errors. The headless test boot re-raises so real errors surface. |
| Engine round structure | `pbCommandPhase` (choices; player side first, then AI — *simultaneous execution after both*) → `pbAttackPhase` (switches, items, moves by priority/speed) → `pbEndOfRoundPhase` (weather, status, forced switches). `turnCount++` per round. Battler index = 2n+side; side = `i % 2` (even = player). |
| Action legality (engine-native) | `pbCanChooseMove?` (PP/Encore/battler), `pbCanShowFightMenu?` (Encore/Struggle), `pbCanShowCommands?` (false = multi-turn lock), `pbCanSwitchOut?`/`pbCanChooseNonActive?`/`pbCanSwitchIn?` (scene arg must be nil or a scene object — `false` raises `NoMethodError` inside `partyScene&.pbDisplay`). |
| Boss endure | `pbReduceDamage` (section 178) references `PBEffects::Endure_boss`, which is **defined nowhere in Scripts.rxdata** — the shipped game defines it in `PluginScripts.rxdata`, which is not part of this pack. The headless boot defines it with a free index (arrays auto-extend; unset = nil = false). This is harness-only; no shipped script is modified. |
| `MODO_SIN_GRINDEO` | Top-level constant 149 from section 008, read by `Pokemon#calcHP/calcStat` guarded by `$game_switches &&`. Headless boot loads 008 and provides minimal switch/variable stubs. |
| Gen/mechanics | MECHANICS_GENERATION = 9 (Gen 9 data incl. `types.dat`); damage/accuracy formulas standard Essentials v20+; accuracy check is `pbRandom(100) < base·acc/eva` (verified live in T1: Thunder 8/10 with misses at rolls 72/99 vs base 70). |
| Data | Real PBS Marshal dumps (Spanish names — move names in outputs like “Lanzallamas”/“Tierra Viva” are the game’s own localized names). `ribbons.dat` load prints a non-fatal skip (nil length) in the headless boot only. |

## 2. What Engine 2.0 is

A chess-engine-style recommender that maximizes the probability of winning
the **entire battle**, built strictly on the game’s own rules:

```
live battle ──Marshal snapshot──> twin (real engine, TwinBehavior)
    └─ ActionSpace   : legality decided ONLY by engine checks
    └─ Search        : simultaneous-round adversarial expectimax;
                       successors ONLY via TurnDriver (real pbAttackPhase +
                       pbEndOfRoundPhase); TT keyed by StateSummary;
                       iterative deepening; node/time budgets; metrics
    └─ Evaluator     : win-probability estimate (logistic squash)
    └─ integration   : one redefined method, HUD-hash contract, fallback
```

Key architectural decisions:

- **TwinBehavior module, not a class hierarchy**: the twin from a live
  battle is a Marshal snapshot of the real battle object with the module
  extended into it. The snapshot keeps the live battle’s own class, so
  format-specific behavior (Battle Arena etc.) is preserved. Only `@scene`
  is touched (swapped to `NullScene` during the dump, restored after).
- **`TurnDriver` is the only successor-state authority**: every search node
  executes a full real round (`pbCommandPhase` choices are injected, then
  `pbAttackPhase` + `pbEndOfRoundPhase` run). No simulator, no cloned
  formulas.
- **Choices are localized** at injection time: the engine mutates
  `@choices` entries in place (`pbCalculatePriority` appends element [4];
  cancels rewrite elements) and `Battle::Move` objects carry per-battle
  state, so a choice built for one battle is re-bound to the target battle’s
  own move objects before injection. (Found via a corrupted best-action bug:
  the recorded action hash was the same object the engine had rewritten to
  `[:None, 0, nil, -1, 0]`.)
- **No alias chains**: the integration redefines
  `Battle#competitive_coach_recommendation` (loaded last, so it wins) and
  captures the previous implementation as an `UnboundMethod`
  (`PRE_2_0_RECOMMENDATION`) for clean fallback. Nothing existing is edited.
- **Isolation**: engine2 defines nothing outside `CoachEngine2`, `Battle`
  (one method), and `Battle::Scene` (guarded `USE_ABILITY_SPLASH` const that
  is a no-op in-game). Verified structurally (T6/T4): no `Input`, `Graphics`,
  `Game_Map`, `Game_Player`, `Game_Temp`, `SpriteSet`, `Scene_Map`,
  `PokemonBag`, `Window` classes; zero `alias` statements.

## 3. Semantics verified live (differential against the real engine)

| Behavior | Result |
|---|---|
| Real damage | Earthquake vs Snorlax: 73–88 dmg range at Lv50; deterministic per seed; roll policies (:min/:max/:median) produce distinct outcomes as expected. |
| Thunder accuracy | 8/10 sampled hits, base 70; misses at rolls 72 and 99 (`roll < base·acc/eva`). |
| Marshal round-trip | Live twin (cyclic refs incl. AI ↔ battle) dumps/loads intact; snapshot-of-snapshot (the search clone path) verified. |
| Switching mid-round | `pbAttackPhaseSwitch` executes before moves; switching into a lethal EQ is correctly fatal (T1: Malamar KO’d on entry). |
| Posthumous actions | A faster Heracross OHKO means ALL of Malamar’s possible action choices yield one identical post-KO state — no value can leak to a dead battler (T2). |
| No Guard | Thunder hits under :min/:max/:median roll policies and through +6 evasion — roll-independent by the real rules (T4). |
| Contrary + Superpower | Atk/Def go +1 per use through the real Contrary path; boosts persist and compound (+2), and the third use against a wall does strictly more damage than an unboosted fresh battle’s (445 vs 329, T5). |
| StatDownMove on KO | The real engine **skips the self stat change when the target’s side is all fainted** (`return if @battle.pbAllFainted?`). Engine 2.0 inherits this rule untouched; tests were adjusted to the engine, not vice versa. |
| Illusion | Zoroark’s Illusion breaks on damage (message verified); entering disguised as the last party member is engine behavior. |
| Damage capping | `pbReduceDamage` caps at the target’s current HP; overkill is not recorded — benchmarks/tests measure growth through real rounds, not capped deltas. |
| Forced replacements | After a faint the twin auto-picks the first able party member (documented policy; no UI headless). The search may enumerate replacements via `TurnDriver#step!`’s replacements hash. |

## 4. Search model and approximations (READ THIS)

Honest scope statement — what the search is and is not today:

- **Round model is exact and simultaneous**: both sides’ joint actions are
  chosen, then one real engine round executes. Our side maximizes; the foe
  minimizes (`:adversarial`) or uses the game’s own AI choice
  (`:game_ai`, via `@battleAI.pbDefaultChooseEnemyCommand` — note `@battleAI`
  is an ivar with no public reader).
- **Chance is approximated by the :median roll policy**: every RNG draw
  returns max/2, collapsing chance nodes into one representative outcome.
  Outcomes the rules make roll-independent (No Guard, fixed damage) are exact
  under this policy by construction; everything else is an estimate.
  Exact chance enumeration (hit/miss/crit/damage-roll branching against the
  pinned-RNG interface) is designed-for but NOT yet implemented. The
  evaluation values are therefore estimates, not probabilities.
- **Evaluator**: logistic-squash of threat/HP/status/hazard terms, exact 1.0
  / 0.0 only at terminal decisions. Calibration is pending playtesting; it
  is documented as an estimate everywhere it is surfaced.
- **Iterative deepening with node/time budgets**; depth-aware TT (deeper
  results replace shallower, never the reverse); move ordering (expected
  power × effectiveness, switches last). Adaptive-depth beyond budget-driven
  deepening (forcing-line extensions, endgame exhaustive solving, selective
  reductions) is not yet implemented.
- **Belief states**: the twin contains only what the client legitimately
  sees (battle state). No hidden information is assumed. Explicit belief
  tracking for unrevealed properties (opponent sets/moves) is not yet
  implemented; the foe action space uses the visible team.

## 5. Multiplayer / security boundary

- The twin is built exclusively from the live battle object the client
  already holds (Marshal snapshot). No auth, anti-cheat, debug or hidden
  routes are touched; no private opponent data beyond what the client
  legitimately receives; no scanning or flooding. The multiplayer RNG
  adapter (`anil_rework_rng`) is routed into the deterministic twin RNG only
  inside the snapshot — the live battle is untouched.
- The recommendation path is read-only on the live battle (one cache ivar on
  the battle object, namespaced `@_coach2_*`).

## 6. Verification performed (all numbers real, none invented)

| Suite | Result | What it covers |
|---|---|---|
| T1 twin smoke | 10/10 | species build, twin build, start sequence, real damage, determinism, roll-policy sensitivity, Marshal round-trip of a live twin, switches, Thunder accuracy sampling. |
| T2 mandatory regressions | 17/17 | the six AGENT_PROMPT scenarios: Steelix KO-on-entry (no false safe switch; sack must be explicit), faster Heracross OHKO (no posthumous action value), Glimmora free KO preserved (value 1.0, no hard-switch), No Guard + Thunder under all roll policies and max evasion, Contrary + Superpower inversion/compounding/effect-on-damage, out-of-battle isolation. |
| T3 from_live | 8/8 | Marshal-snapshot fidelity: state equality, identical successors under identical actions (differential), scene restoration, snapshot-of-snapshot, search on mid-battle snapshots. |
| T4 integration | 8/8 | HUD hash contract, per-(turn,HP) caching, disable switch with clean fallback to the pre-2.0 chain (the old v5–v18 chain is genuinely loaded in the headless boot and its hash was served), foe side never coached, budgets, structural isolation. |
| T5 rxdata smoke | PASS | the SHIPPED `game/Scripts.rxdata` is parsed by an independent reader inside the Ruby runtime, section 617 evaluated, and it produces a correct recommendation (W=100% free-KO line). |
| Rxdata build | verified | 617 entries; 616 originals byte-identical (raw blobs reused); new section last; inflated content equals the engine2 concatenation byte-for-byte. Baseline checksum unchanged. |
| Benchmarks | see BENCHMARKS.md | measured in this sandbox (wasm32-wasi). No native/desktop numbers are claimed. |

Environment: Ruby 3.3.3 wasm32-wasi under wasmtime 48 (Python driver); real
PBS data; real engine scripts. What could NOT be tested here: actual RGSS
sprite drawing (the HUD’s visual layer), in-game scene timing, and native
CPU performance. The HUD path is exercised only up to the hash contract.

## 7. Known limitations

1. Chance nodes are collapsed (:median policy) — see §4. Values are
   estimates, not exact win probabilities, except at terminal decisions.
2. In-game `from_live` Marshal-dumps the live battle; if any battle variant
   holds an undumpable object beyond the scene (e.g. a network socket), the
   coach degrades to the old chain for that battle (rescue path tested in
   T4). Unverified against the real multiplayer client.
3. Forced replacements after faints are auto-picked (first able) rather than
   enumerated; deliberate-sac versus forced-sac distinction at the search
   level will need replacement enumeration (API exists).
4. Foe action space uses the visible opposing team; no belief modeling of
   unrevealed Pokémon yet.
5. The evaluator is uncalibrated (no playtest data yet); only its ordering
   properties are relied upon in tests.
6. Synchronous computation on menu open (desktop ≤3 s, JoiPlay ≤1.8 s
   budgets). No background thread yet.
