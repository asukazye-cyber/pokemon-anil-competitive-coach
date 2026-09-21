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
- **Chance: exact for the first path-altering roll of a round, :median for
  everything else.** Each candidate round is executed once as a *probe* (all
  RNG at the median band); the probe's roll log then locates the round's first
  accuracy event, whose move, threshold and probability are measured from the
  live engine — never assumed. Identification is PROVEN differentially:
  pinning the roll just below the threshold must reproduce the probe, pinning
  it at the threshold must change it; a round that fails either test is not
  branched and is counted as `unbranched` in the metrics (never silent). The
  branched outcomes carry the measured probabilities (`pbRandom(100) <
  base·acc/eva`), and Σp = 1 is asserted in T6. Damage magnitude is
  discretized at `:coarse` (quadrature over {min, mid, max} = 1/16, 14/16,
  1/16 — measured, not derived) and critical hits at `:fine`; later accuracy
  rolls and secondary-effect procs keep the :median policy.
  Branch budget: `max_outcomes` (default 8) caps the outcomes per chance node.
  The tail is taken from the probability-sorted order and folded into ONE
  `[:folded]` outcome carrying the probe (median-band) state, so a capped
  enumeration degrades toward the median estimate instead of inflating some
  other branch. `:fine` is only used when the cap can hold its 33 branches.
- **Evaluator**: logistic-squash of threat/HP/status/hazard terms, exact 1.0
  / 0.0 only at terminal decisions. Calibration is pending playtesting; it
  is documented as an estimate everywhere it is surfaced.
- **Iterative deepening with node/time budgets**; depth-aware TT (deeper
  results replace shallower, never the reverse); move ordering (expected
  power × effectiveness, switches last, scored for the side that will actually
  execute it — our side against the foe, the foe against us). Adaptive depth
  is implemented and measured: forcing-line extensions (KO / forced
  replacement continue past nominal depth), selective reductions (late
  ordered moves searched shallower), endgame deepening, and ε-pruning of
  hopeless branches (bounded, and observed firing in T6).
- **Belief states**: the twin contains only what the client legitimately
  sees (battle state); no hidden information is assumed. The `:revealed`
  policy additionally restricts the foe's action space to moves it has been
  seen use, and `:full` (default) uses the visible team's real movesets —
  which is still only what the client holds (T6 pins both).

## 5. Multiplayer / security boundary

- The twin is built exclusively from the live battle object the client
  already holds (Marshal snapshot). No auth, anti-cheat, debug or hidden
  routes are touched; no private opponent data beyond what the client
  legitimately receives; no scanning or flooding. The multiplayer RNG
  adapter (`anil_rework_rng`) is routed into the deterministic twin RNG only
  inside the snapshot — the live battle is untouched.
- The recommendation path is read-only on the live battle (one cache ivar on
  the battle object, namespaced `@_coach2_*`).
- **BattleSync isolation gate.** A Marshal snapshot of a battle inside an
  active co-op context keeps the rework's network wrappers — `pbAttackPhase`
  (turn bundle fail-safe + attack barrier), `pbEndOfRoundPhase` (end-of-turn
  HP reconciliation), `pbJudge` (drains pending HP syncs) and
  `pbSwitchInBetween` (broadcasts a switch choice or blocks waiting for the
  peer). Those wrappers read module-level sync state, which no per-instance
  override on the twin can neutralise, so *simulating* a round inside the
  twin would act on the peer connection on behalf of the live battle. Since
  that cannot be verified headlessly, `TwinFactory.from_live` REFUSES such a
  snapshot (`CoachEngine2::TwinIsolationError` → the HUD falls back to the
  v27 chain). `CoachEngine2.allow_sync_twins = true` is the documented
  override for after it has been verified on the real client. Single-player
  battles are unaffected (`BattleSync.active_context` is nil there).

## 6. Verification performed (all numbers real, none invented)

| Suite | Result | What it covers |
|---|---|---|
| T1 twin smoke | 10/10 | species build, twin build, start sequence, real damage, determinism, roll-policy sensitivity, Marshal round-trip of a live twin, switches, Thunder accuracy sampling. |
| T2 mandatory regressions | 17/17 | the six AGENT_PROMPT scenarios: Steelix KO-on-entry (no false safe switch; sack must be explicit), faster Heracross OHKO (no posthumous action value), Glimmora free KO preserved (value 1.0, no hard-switch), No Guard + Thunder under all roll policies and max evasion, Contrary + Superpower inversion/compounding/effect-on-damage, out-of-battle isolation. |
| T3 from_live | 8/8 | Marshal-snapshot fidelity: state equality, identical successors under identical actions (differential), scene restoration, snapshot-of-snapshot, search on mid-battle snapshots. |
| T4 integration | 8/8 | HUD hash contract, per-(turn,HP) caching, disable switch with clean fallback to the pre-2.0 chain (the old v5–v18 chain is genuinely loaded in the headless boot and its hash was served), foe side never coached, budgets, structural isolation. |
| T5 rxdata smoke | PASS | the SHIPPED `game/Scripts.rxdata` is parsed by an independent reader inside the Ruby runtime, section 617 evaluated (all 8 engine2 files incl. chance/beliefs), and it produces a correct recommendation (W=100% free-KO line). |
| T6 milestones | 21/21 | exact chance: probabilities sum to 1, Thunder p_miss = 0.30 measured, No Guard single-outcome, damage bands {1/16,1/16,14/16}, crit 1/24 at :fine; expectimax decomposition equals Σ p·eval exactly; ε pruning bounded + fires; deterministic; adaptive depth boosts; KO extensions; replacement enumeration (order independence, adversarial foe counter); beliefs (:revealed excludes unobserved moves). |
| T7 post-merge audit | 24/24 | one regression per finding in §8: branch-cap collapse (`fold` arity), folded-mass accounting, cap-aware `:fine`, accuracy-event identification (incl. Trick Room order flips and the `:game_ai` path), choice aliasing (game-AI foe + multi-turn locks), the snapshot twin protections on the real `from_live` path, forced replacement on a snapshot, `StateSummary` coverage, foe reply ordering, replacement enumeration, and the BattleSync gate. Runs separately (`tests/headless/run_audit.rb`) so the 64-check acceptance gate keeps the shape it had at merge time. |
| Rxdata build | verified | 617 entries; 616 originals byte-identical (raw blobs reused); new section last; inflated content equals the engine2 concatenation byte-for-byte (93,358 chars after the audit fixes). Baseline checksum unchanged. Rebuilt from the corrected sources and re-verified by the T5 smoke. |
| Benchmarks | see BENCHMARKS.md | measured in this sandbox (wasm32-wasi). No native/desktop numbers are claimed. |
| Full suite | **64/64 + smoke** | T1 10 + T2 17 + T3 8 + T4 8 + T6 21, plus the shipped-rxdata smoke, all against the real engine + real data — re-run to the same result after the §8 fixes (T7 24/24 on top). |

Environment: Ruby 3.3.3 wasm32-wasi under wasmtime 48 (Python driver); real
PBS data; real engine scripts. What could NOT be tested here: actual RGSS
sprite drawing (the HUD’s visual layer), in-game scene timing, and native
CPU performance. The HUD path is exercised only up to the hash contract.

## 7. Known limitations

1. Per round, one path-altering chance event (the first accuracy roll) is
   branched; later accuracy rolls and secondary-effect procs keep the
   :median policy (counted in metrics as unbranched). Damage magnitude is
   discretized at :coarse (mid band quadrature). A round whose accuracy event
   cannot be identified differentially is not branched at all — it keeps the
   probe (median) value and is counted, so the metrics field `unb=N` is the
   honest bound on how many chance nodes fell back to estimates. When the
   outcome cap truncates an enumeration, the dropped mass becomes a single
   `[:folded]` outcome carrying the probe state: the value is then a weighted
   mix of exact branches and the median estimate, never a mis-attributed
   probability.
2. Replacement enumeration covers one forced battler per side per round
   (singles). Doubles products are a documented next step.
3. In-game `from_live` Marshal-dumps the live battle; if any battle variant
   holds an undumpable object beyond the scene (e.g. a network socket), the
   coach degrades to the old chain for that battle (rescue path tested in
   T4). Unverified against the real multiplayer client — which is exactly why
   a battle inside an active BattleSync context is now REFUSED outright
   instead of simulated (§5 gate): the network wrappers sit on phases the
   twin cannot detach, and the hazard (acting on the peer connection on behalf
   of the live battle) is worse than losing one recommendation.
4. `:revealed` belief policy is optimistic when the foe has unobserved
   moves (undercounts their options); default `:full` uses only what the
   client's own battle object legitimately contains.
5. The evaluator is uncalibrated (no playtest data yet); only its ordering
   properties are relied upon in tests. Exact values come from terminal
   decisions and the enumerated chance decomposition.
6. Synchronous computation on menu open (desktop ≤3 s, JoiPlay ≤2 s
   budgets). No background thread yet.

---

## 8. Post-merge audit (findings and fixes)

Method: re-read all eight Engine 2.0 files against the real engine scripts and
against the claims in §4/§6, then *reproduce* every suspicion in a throwaway
harness against the merged code before touching anything. Every finding below
is measured ("was" = merged code, "now" = fixed code); each is pinned by a
check in `tests/headless/t7_audit.rb` (24/24). Nothing here is a guess about a
line that was not executed.

| ID | Defect (merged code) | was | now |
|---|---|---|---|
| A | `ChanceEnumerator#fold` defined with 4 params, called with 3 → the cap path raised `ArgumentError`, swallowed by the blanket rescue into ONE `[:fallback]` outcome, p=1.0. Hit in every endgame round (see A2). | `outcomes=1 tags=[[:fallback]]` | 9 outcomes, Σp=1.0, no rescue taken |
| A2 | `:fine` (33 branches) force-upgraded into an 8-outcome cap; the truncated tail was sliced UNSORTED and its mass dumped into the largest outcome. | `miss_p=0.707` for a 70-acc move; 16 rounds | `miss_p=0.30` + one `[:folded]` 0.407; `:fine` only when `max_outcomes ≥ 33`, else exact `:coarse` (6 rounds) |
| B | The round's first accuracy roll was attributed using the PARENT state's stale `@priority`/`@choices` (the previous round's order). Trick Room, priority moves, speed changes and switches all flip it. | `miss_p=0.30` (our Thunder's threshold) branched for the foe's Fire Blast, whose truth is 0.15 | order + executed choices read from the probe round; identification proven differentially (pin below = probe, pin at = changed); `miss_p=0.15` |
| B2 | With `foes: :game_ai` the foe's executed choice was never consulted, so no accuracy event could be identified — a silent 100%-hit assumption on the foe's move. | no `:miss` branch, no `unb` count | executed joint action recorded as plain data (`coach_choices`); `miss_p=0.30` measured for the AI's Thunder |
| B3 | `assign_side` captured `battle.choices[i]` BY REFERENCE for multi-turn locks and the game AI; `inject!`'s `pbClearChoice` rewrites that array IN PLACE → the action was injected as `[:None]` and the battler did nothing. | a charging Solar Beam never fired; a `:game_ai` foe never moved in any round of any search | choices copied at capture and again before clearing; Solar Beam fires on round 2 (271→179), Thunder reaches our Snorlax (271→196) |
| C | `StateSummary` (TT key AND differential oracle) ignored field effects, counted battler effects without recording WHICH were set, and ignored PP → colliding keys return another state's value. | Yawn-vs-Embargo and same-count-different-effect pairs compared EQUAL | field/side/position pairs, effect identity, PP, ability, item, `turnCount`; object values (Illusion's Pokemon) reduced to clone-stable fingerprints; identical states still identical |
| D | `action_score` always scored against `@side`'s opponents, so the foe's most dangerous reply ranked last. | `[Bola Sombra, Lanzallamas]` (Lanzallamas is 4× on our Steelix) | `[Lanzallamas, Bola Sombra]`; our own ordering unchanged |
| E | A `from_live` snapshot of a plain `Battle` — the path the game actually uses — kept the engine's RNG and every `TwinBattle`-only protection, because the overrides lived on the wrong class. | roll log 0/0, identical rounds = false, `outcomes=[[:deterministic], 1.0]`; a faint reached the party-screen replacement path | log 11/11, identical rounds = true, 4 enumerated outcomes; forced replacement resolved on the snapshot (Zoroark in, no screen). All protections now live in `TwinBehavior` |
| E2 | Same snapshot taken inside an active BattleSync context inherits network wrappers on four phases that consult module-level sync state — no per-instance override can neutralise them. | would simulate rounds against the live peer connection | refused: `TwinIsolationError` → `recommend_for` nil → v27 chain serves the HUD; `allow_sync_twins` is the documented override; single-player unaffected |

Also fixed in the same pass, each with its own check or covered by the above:
replacement candidates enumerated on the pre-round state (a fainted mon was
offered and then silently rejected by the engine's own legality test); pin
verification that compared only a roll's max, not the pinned value; outcomes
tagged `:hit` in rounds with no accuracy event; a failed identification not
counted in `unbranched` (the metrics header promises "never silent"); an empty
roll log from an uninstrumented battle passing as "deterministic";
`Search#config` returning nil (`attr_reader :config` over `@cfg`); the unsettable
`@abort` flag (now `abort!`); the ambiguous `ch=2/60` metrics field (now
`ch=2/6 unb=0`); `TurnDriver.execute`'s accepted-and-ignored `foe_ai:` keyword.

Verification after the fixes: full suite **64/64 + shipped-rxdata smoke** (same
gate as at merge), T7 **24/24**, `game/Scripts.rxdata` rebuilt (617 entries,
616 byte-identical, new section evaluates and recommends correctly),
`baseline/Scripts.rxdata` checksum unchanged.
