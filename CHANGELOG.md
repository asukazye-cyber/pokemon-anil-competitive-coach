# CHANGELOG

## [Unreleased] — Coach Engine 2.0

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
