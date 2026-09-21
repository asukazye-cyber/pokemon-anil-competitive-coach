# CHANGELOG

## [Unreleased] — Coach Engine 2.0

### Fixed (post-merge audit)

Every item below was REPRODUCED against the merged code before the fix — the
`was:` lines are measured harness output, not inference — and is pinned by a
regression check in `tests/headless/t7_audit.rb` (24 checks; run separately so
the 64-check acceptance gate keeps the shape it had at merge time). The suite
still passes 64/64 + the shipped-rxdata smoke after the fixes, and
`game/Scripts.rxdata` was rebuilt from the corrected sources.

- **Chance enumeration collapsed to a single outcome whenever the branch cap
  was hit** (`chance.rb`): `fold` was defined with 4 parameters and called
  with 3, so the cap path raised `ArgumentError`, which the blanket rescue
  turned into one `[:fallback]` outcome with p=1.0 — silently. The cap is hit
  in EVERY endgame round, because the search force-upgrades 1v1 rounds to
  `:fine` (33 branches) while the default `max_outcomes` is 8.
  `was: outcomes=1 tags=[[:fallback]] (ArgumentError: given 3, expected 4)`
- **The outcome cap mis-accounted the mass it dropped** (`chance.rb`): the
  folded tail was sliced from the UNSORTED branch list, and the mass was
  dumped into the largest outcome, inflating a 70%-accuracy move's miss branch
  to 0.707. The tail is now taken from the probability-sorted order and folded
  into ONE extra `[:folded]` outcome carrying the probe (median-band) state;
  every fold is counted in `unbranched`.
  `was: [[:miss], 0.707] … now: [[:miss], 0.30] + [[:folded], 0.407]`
- **The endgame `:fine` upgrade ignored the outcome budget** (`search.rb`):
  upgrading 33 branches into an 8-outcome cap truncated most of the
  distribution it was meant to enumerate. `:fine` is now taken only when
  `max_outcomes >= ChanceEnumerator::MAX_FINE_BRANCHES`; otherwise the exact
  `:coarse` quadrature is enumerated. On the trivial endgame position that is
  6 rounds and 3 exact outcomes per chance node instead of 16 rounds and a
  collapsed enumeration.
- **The accuracy event was identified from the PREVIOUS round's execution
  order** (`chance.rb`): the enumerator read `@priority`/`@choices` off the
  parent state, which describes the last round. Trick Room ending, priority
  moves, speed changes and switches all flip the order, so a threshold
  measured for one move was applied to another move's roll — and the
  one-sided verification passed anyway. Order and executed choices now come
  from the probe round itself, and identification is PROVEN differentially:
  pinning the roll just below `thr` must reproduce the probe while pinning it
  at `thr` must change it. Anything else is not branched and is counted.
  `was: miss_p=0.30 branched for the foe's Fire Blast (85 acc; truth 0.15),
  because our Thunder's threshold was measured instead — now 0.15`
- **A choice read from the engine's own `@choices` was destroyed before
  injection** (`turn_driver.rb`): `pbClearChoice` rewrites the existing array
  IN PLACE, and `assign_side` captured that array BY REFERENCE for (a) the
  game-AI foe model and (b) battlers locked into a multi-turn attack. Both
  were injected as `[:None]`, so those battlers did nothing at all.
  `was: a charging Solar Beam never fired; a :game_ai foe never moved`
- **`from_live` snapshots of a plain `Battle` were not twin-protected**
  (`twin_battle.rb`): RNG routing, the dex/exp/money no-ops, the forced-
  replacement hooks and the message capture were defined on `TwinBattle` only,
  while the path the GAME uses is a Marshal snapshot of a plain `Battle`
  extended with `TwinBehavior`. Such a twin kept the engine's `pbRandom`:
  rounds were non-reproducible, chance enumeration reported "deterministic"
  from an empty roll log, and a faint reached the party-screen replacement
  path. All of it now lives in `TwinBehavior`, so both construction paths are
  the same twin.
  `was: rng log 0/0, identical rounds=false, outcomes=[[:deterministic], 1.0]
  — now: log 11/11, identical rounds=true, 4 enumerated outcomes`
- **Multiplayer isolation gate** (`twin_battle.rb`): a snapshot of a battle
  inside an active BattleSync context inherits the rework's network wrappers
  on `pbAttackPhase` (turn bundle fail-safe + attack barrier),
  `pbEndOfRoundPhase` (end-of-turn HP reconciliation), `pbJudge` (drains
  pending HP syncs) and `pbSwitchInBetween` (broadcasts a switch choice or
  blocks waiting for the peer). They consult module-level sync state that no
  per-instance override can neutralise, so a simulated round would touch the
  peer connection on behalf of the LIVE battle. `from_live` now raises
  `CoachEngine2::TwinIsolationError` in that case and the HUD falls back to
  the v27 chain; `CoachEngine2.allow_sync_twins = true` is the documented
  override, to be used only after verification on the real client.
- **Transposition keys collided** (`turn_driver.rb`): `StateSummary` — the TT
  key AND the differential oracle — ignored field effects entirely (Trick
  Room changes the execution order), recorded only the COUNT of set battler
  effects, and ignored PP. A collision silently returns another state's value.
  It now covers field/side/position effect pairs, battler effect identity, PP,
  abilities, items and battler `turnCount`, with object values (Illusion holds
  a Pokemon) reduced to clone-stable fingerprints so two snapshots of the same
  battle still compare equal.
- **The adversary's replies were ordered against its own team** (`search.rb`):
  `action_score` always targeted `@side`'s opponents, so the foe's most
  dangerous answer ranked last.
  `was: [Bola Sombra, Lanzallamas] for a Gengar facing our Steelix
  (Lanzallamas is 4x) — now: [Lanzallamas, Bola Sombra]`
- **Replacement candidates were enumerated on the pre-round state**
  (`search.rb`): a Pokémon that faints in the same round could be offered as a
  replacement and was then silently rejected by the engine's own
  `pbCanSwitchIn?` during the re-run (the auto-pick substituted another mon,
  so the enumerated value belonged to a different line). They are now
  enumerated on the outcome (child) state, where the replacement happens.
- **`foes: :game_ai` rounds could not identify any chance event**
  (`chance.rb`): the foe's executed move existed only in the engine's
  `@choices`, which the round clears as each battler acts. `TurnDriver` now
  records the executed joint action as plain data on the clone
  (`coach_choices` — no move objects, which would drag the parent battle's
  object graph into every Marshal clone).
- Smaller, same pass: pin verification compared only the roll's max and not
  the pinned value; outcomes were tagged `:hit` in rounds with no accuracy
  event at all; a failed identification was not counted in `unbranched` (the
  header promises "never silent"); an empty roll log caused by an
  uninstrumented battle passed as "deterministic"; `Search#config` returned
  nil (`attr_reader :config` over a `@cfg` ivar); `@abort` was read but could
  never be set (now `Search#abort!`); the metrics field `ch=2/60` was
  ambiguous between "60 outcomes" and "6 outcomes, 0 unbranched" (now
  `ch=2/6 unb=0`); `TurnDriver.execute`'s `foe_ai:` keyword was accepted and
  ignored; dead locals in `enumerate`.

### Added (post-merge audit)

- `tests/headless/t7_audit.rb` + `tests/headless/run_audit.rb`: 24 regression
  checks, one per audit finding, each asserting the fixed behaviour.
- `ChanceEnumerator::MAX_FINE_BRANCHES`, `CoachEngine2::TwinIsolationError`,
  `CoachEngine2.allow_sync_twins`, `Search#abort!`/`Search#aborted?`,
  `TwinBehavior#coach_choices`, `TurnDriver.plain_choice`.

### Added (milestone update: exact chance, adaptive pruning, beliefs)

- **Exact chance enumeration** (`engine2/chance.rb`): round outcomes
  enumerated with probabilities MEASURED against the real engine — accuracy
  thresholds by bisection on standalone `pbAccuracyCheck` calls, crit rates
  from the engine's own roll request, damage variance as 3-point (:coarse)
  or 16-point (:fine) uniform bands. Rolls are classified by the engine's
  own call stack; every pinned branch is verified (pin-landing + state
  equality); unbranched events are counted, never silent. No Guard /
  100%-accuracy moves correctly produce no branch.
- **Expectiminimax search** (`engine2/search.rb` rewritten): chance nodes
  with exact event probabilities; Star1-style ε-bounded chance pruning
  (pessimistic bounds — pruning never flatters a line); α-β with TT value
  bounds; aspiration windows with re-search; late-move reductions;
  extensions for KO rounds and forcing lines; small-root/endgame depth
  boosts with :fine granularity in endgames.
- **Forced-replacement enumeration**: a faint that forces a switch-in is a
  DECISION node — our replacements under MAX (deliberate sacrifice is
  explicit and rated), the foe's under MIN (their counter is assumed).
  Verified party-order independence and adversarial counter assumption.
  Hooks both engine paths (player `pbGetReplacementPokemonIndex`, foe
  `pbSwitchInBetween`).
- **Opponent beliefs** (`engine2/beliefs.rb`): explicit BeliefState over
  observed foe moves (from the engine's own `@movesUsed`/`@lastMoveUsed`
  records — client-visible history). Policies: `:full` (default; uses only
  what the client's battle object legitimately holds) and `:revealed`
  (models only observed moves; documented optimistic bias). ActionSpace and
  Evaluator honor the policy.
- **T6 milestone suite** (21 checks): probability sums, measured Thunder
  miss = 0.30, No Guard single-outcome, damage band weights, crit 1/24,
  exact expectimax decomposition, ε-bound + firing, determinism, adaptive
  depth, KO extensions, replacement enumeration (order independence,
  adversarial foe), belief filtering.
- **Tracked harness data**: `Data/` (game .dat + generated types.dat) is now
  committed so the headless suite survives environment restores.

### Fixed

- Shipped rxdata section now includes ALL engine2 files (chance.rb and
  beliefs.rb were missing from the build list — caught by the shipped-
  artifact smoke test falling back to the old coach chain).
- `@priority` entries are `[battler, ...]` (battler objects, not indices).
- Foe forced replacements go through `pbSwitchInBetween`, not
  `pbGetReplacementPokemonIndex` — both hooked now.

### Added

- **Engine 2.0 core** (`engine2/`): `TwinBattle`/`TwinBehavior` (real
  `Battle` subclass + a module extendable into Marshal snapshots of live
  battles), `NullScene`, `DeterministicRNG` (:free/:min/:median/:max roll
  policies, pin, roll log), `DummyTrainer`, `TwinFactory.build/from_live`.
- **TurnDriver** — the sole successor-state authority: injects joint
  choices (localized to the target battle’s own objects), runs the real
  `pbAttackPhase` + `pbEndOfRoundPhase`, hashable `StateSummary`,
  deep-copy helper.
- **ActionSpace** — legal joint-action generation using only engine
  legality checks (`pbCanChooseMove?`, `pbCanShowFightMenu?`,
  `pbCanShowCommands?`, `pbCanSwitchOut?`, `pbCanChooseNonActive?`,
  `pbCanSwitchIn?`); multi-turn locks keep the engine’s own choice; fainted
  battlers yield no actions.
- **Search** — simultaneous-round adversarial expectimax (our side max ×
  foe min, or foe = the game’s own AI via `pbDefaultChooseEnemyCommand`),
  iterative deepening, depth-aware transposition table, node/time budgets,
  move ordering, full metrics (nodes, unique rounds, TT hits/stores,
  effective branching, completed depth, elapsed, PV).
- **Evaluator** — win-probability estimate (logistic squash of threat/HP/
  status/hazard terms); exact 1.0/0.0 only at terminal decisions. Explicitly
  an estimate pending calibration (see AUDIT §4).
- **In-game integration** (`engine2/integration.rb`, shipped as the final
  rxdata section): redefines `Battle#competitive_coach_recommendation` (no
  aliases; loaded last), captures the pre-2.0 implementation for clean
  fallback, HUD hash contract (`best`/`alternative`/`confidence_dots`),
  per-(turn, HP) caching, desktop vs JoiPlay budget profiles, runtime
  disable switch (`CoachEngine2.enabled=`).
- **New game data build** — `game/Scripts.rxdata`: all 616 original sections
  byte-identical + one new final section (“MOD_ Coach Engine 2.0”, id
  20260921). The original `baseline/Scripts.rxdata` is untouched. Built by
  `tools/build_engine2_rxdata.py` with round-trip, identity, count/order and
  content verification.
- **Headless test infrastructure**: `tests/headless/boot.rb` (dependency-
  ordered boot of the real engine + PBS data), `stubs.rb` (RGSS stubs;
  `PBDebug.pbPrintException` re-raises so `logonerr` can’t swallow engine
  errors), and five suites — T1 twin smoke (10/10), T2 mandatory
  regressions (17/17), T3 from-live fidelity (8/8), T4 integration (8/8),
  T5 shipped-rxdata smoke (PASS). 43/43 total.
- **Benchmarks** (`tests/headless/bench.rb`, `BENCHMARKS.md`) measured in
  the verification environment (wasm32-wasi): ~22–34 search rounds/s;
  trivial positions solve to proven wins in ~0.1 s; budgets respected.

### Fixed / hardened (found by differential testing)

- `pbCanSwitchIn?`/`pbCanSwitchOut?` must be called without a scene
  argument (passing `false` raises inside `partyScene&.pbDisplay`) — switch
  actions were silently missing from the action space.
- Choices injected into a battle are re-bound to that battle’s own
  `Battle::Move` objects and duplicated — the engine mutates `@choices`
  entries in place and move objects carry per-battle state.
- `@battleAI` has no public reader; the game-AI foe model reads the ivar.
- Headless harness defines `PBEffects::Endure_boss` (referenced by the
  engine’s `pbReduceDamage`, defined only in the game’s
  `PluginScripts.rxdata`, which is not part of this pack) and loads section
  008 (`MODO_SIN_GRINDEO`) plus minimal `$game_switches`/`$game_variables`
  stubs for the AI’s mega-evolution gate.
- Forced replacements in twins auto-pick the first able party member
  (previously reached a party-screen UI call that headless cannot serve).

### Notable engine behaviors preserved (not “fixed” — the engine is the
source of truth)

- `StatDownMove` skips the self stat change when the target’s side is all
  fainted (affects Contrary + Superpower compounding when the hit KOs).
- In-battle damage is capped at the target’s remaining HP.
- Illusion breaks on damage; the disguised name appears in switch messages.

### Explicitly not claimed

- Exact win probabilities (chance nodes are collapsed by the :median roll
  policy; see AUDIT §4).
- Native/desktop or JoiPlay performance figures (only the wasm verification
  environment was measured).
- Any in-game visual/UX validation beyond the HUD hash contract (RGSS
  sprite drawing could not be reproduced in this environment).
