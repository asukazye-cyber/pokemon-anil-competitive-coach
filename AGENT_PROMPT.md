# Pokémon Añil/Azul Competitive Coach — Agent Handoff

You are taking over an advanced Pokémon Essentials/Añil battle-coach engineering project. Work as a senior Ruby/Pokémon Essentials battle-engine engineer. The goal is not to keep stacking monkey-patches; the goal is to audit and refactor the Coach into a coherent, testable Engine 2.0 while preserving the game outside battle.

## Source of truth
The repository must be treated as authoritative. Inspect actual files before making claims. The supplied current build contains Coach modules through v27 (`Competitive Coach v27 Pre-Action KO Authority`); do NOT assume the later conversational v28 exists unless it is actually committed. Preserve backups.

## Project intent
The Coach is an in-battle recommendation engine with a minimal HUD (`COACH -> action`, `ALT -> second option` / critical warning). It should maximize battle-winning prospects, not merely immediate damage. It must work for arbitrary teams and for both AI battles and multiplayer using only information legitimately available to the normal client.

Audit the existing experimental layers for duplication, shadowed aliases, contradictory scoring, stale state, hooks outside Battle, and recommendation/HUD inconsistencies.

## Engine 2.0 architecture
Refactor toward clear ownership:
1. `BattleState` / `VirtualState`: complete 6v6 state.
2. `RulesAdapter`: derive behavior from actual Añil/Essentials code and GameData/function codes.
3. `ActionGenerator`: legal moves, switches, deliberate sacks, Mega/form choices.
4. `TurnResolver`: ONLY authority allowed to create successor states.
5. `DamageAccuracyModel`: faithful damage/accuracy/immunity/modifiers.
6. `SearchEngine`: adversarial probabilistic search with iterative deepening, transposition table and strict JoiPlay/Android time budget.
7. `Evaluator`: material, HP, positioning, hazards, tempo, setup, endgame, preservation value.
8. `OpponentModel`: only legitimate current-battle information.
9. `CoachHUD`: presentation only; never compute a separate tactical result.

## Turn semantics
A node represents a complete turn with simultaneous choices. Resolve switches/entry consequences, effective priority, Speed/Trick Room/ties, first action, consequences, KO/can-act check, second action only if legal/alive, then end-of-turn effects. A Pokémon KO'd before acting must never receive value for an action it cannot execute.

## Switch semantics
Hard switching costs the turn. Apply hazards/entry effects, resolve opponent action against the actual incoming Pokémon, reject unsafe ordinary switches, distinguish `SWITCH` from deliberate `SACRIFICE`, and make opponent switching a first-class action.

## Probabilities
Branch tactically meaningful uncertainty instead of blindly using damage*accuracy: contextual hit/miss, No Guard, accuracy/evasion, abilities/items/weather/field, damage rolls, crits, secondary effects, multi-hit and speed ties. Document approximations.

## Systemic interactions
Contrary + Superpower must update future Attack/Defense correctly. Setup moves must change virtual stages and future calculations. No Guard + Thunder must be guaranteed when the real rules guarantee it. Progressively model screens, hazards, weather, terrain, Substitute, Protect, Taunt, Encore, Choice lock, recoil/drain, healing, pivoting, phazing, trapping, status and relevant custom mechanics.

## Mandatory regression tests
1. Steelix capable of KOing Malamar on entry: do not label Switch->Malamar safe; deliberate sack must be explicit and justified.
2. Faster Heracross capable of OHKOing Malamar: do not recommend Knock Off/Desarme as though Malamar acts after death.
3. Glimmora Lv100 308/308 vs Mareep Lv3 16/16 with safe immediate KO: do not arbitrarily hard-switch to Zoroark; preserve free KO unless a concrete strategic line dominates.
4. No Guard + Thunder: guaranteed accuracy where actual game rules say so.
5. Contrary + Superpower: inverted boosts persist in future virtual state and affect search.
6. NPC/map/input isolation: outside battle, NPC interaction, map controls and normal Input must match baseline.

## Audit first
Before changing behavior, map the real battle call graph, Battle/AI/GameData handlers, every Coach script/alias chain, later overrides, dead/duplicate/contradictory code, hooks outside Battle, exact vs heuristic calculations, and actual .dat structures. Produce `AUDIT.md` first.

Then implement Engine 2.0 as a coherent isolated layer loaded at the end where practical. Do not delete unrelated original scripts. Make the Coach easy to disable.

## Performance
Target JoiPlay/Android. Use elapsed-time and node budgets, compact transposition keys, cached immutable rule lookups, low-allocation state transitions, and instrumentation for nodes/depth/ms/cache hits/branches. Keep normal HUD minimal.

## Multiplayer/security
Use only information legitimately received by the normal client via battle state, Team Preview or BattleSync. Do not bypass anti-cheat/debug/auth, hidden routes, authorization, or private opponent data. Do not add scanning/flooding.

## Deliverables
Produce `AUDIT.md`, Engine 2.0 sources/isolated patch, regression harness/results, benchmark notes, a NEW rebuilt `Scripts.rxdata` without overwriting the supplied original, and `CHANGELOG.md`.

Before success claims: run Ruby syntax checks, load/decompress round-trip every Scripts.rxdata entry, verify script count/order except intentional changes, run regressions, and explicitly report unsupported mechanics. Never invent benchmarks, win rates or test passes.