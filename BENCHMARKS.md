# BENCHMARKS — Coach Engine 2.0

All numbers below were measured in the only environment available for
verification: Ruby 3.3.3 **wasm32-wasi** under wasmtime 48, with the real
Añil engine and real PBS data loaded. They are honest for that environment.
Native desktop and JoiPlay/Android performance will differ (expected faster
on native desktop; variable on JoiPlay) — those numbers are NOT claimed
here. Re-run `tests/headless/bench.rb` on target hardware for local figures.

## Search benchmarks (exact chance enumeration ON, desktop budget)

Budgets as shipped: desktop = depth 3 / 600 rounds / 3000 ms / ε 0.02 /
chance :on (coarse); joiplay = depth 2 / 150 rounds / 2000 ms / ε 0.03 /
chance :root.

| Scenario | Best | Value | nodes | rounds | depth | ms | rounds/s |
|---|---|---|---|---|---|---|---|
| A trivial Lv100 vs Lv3 (desktop) | Tierra Viva | 1.00 | 2 | 16 | 1 | 332 | 48.2 |
| B even 1v1 (desktop) | Surf | 0.44 | 13 | 72 | 2 | 3100 | 23.2 |
| C 2-mon side w/ switches (desktop) | Surf | 0.46 | 66 | 67 | 2 | 3051 | 22.0 |
| D same, foe = game AI (desktop) | Surf | 0.64 | 74 | 56 | 3 | 3189 | 17.6 |
| E 2-mon side (joiplay budget) | Surf | 0.46 | 58 | 48 | 2 | 2088 | 23.0 |
| F low-HP endgame, depth-4 budget | Surf | 0.44 | 15 | 64 | 2 | 3067 | 20.9 |
| G raw round unit cost | — | — | — | 30 | — | 1135 | 37.8 ms/round |

## Reading the numbers

- **Exact chance costs depth, honestly reported**: each chance node now
  executes ~4–6 rounds (probe + pinned branches) instead of 1, so within
  the same 3 s budget midgame positions complete depth 2 (they reached 3
  with the old collapsed-chance search). Trivial positions still solve to
  PROVEN wins (A: W = 1.0, terminal, in 0.3 s — iterative deepening stops
  early by design). The game-AI foe model (D) reaches depth 3 because it
  has a single foe branch.
- **Adaptive depth is visible**: A stops at depth 1 because the win is
  proven (not a failure — a solved search). Small root action spaces and
  endgames (≤2 able mons) get +2 depth and :fine chance granularity.
- **Budgets respected everywhere**; ε-pruning and the mass fold keep chance
  nodes within bounds with per-node error ≤ ε (pessimistic side).
- **Throughput** ~18–23 search rounds/s in this wasm environment. A native
  desktop CPU is expected to be several times faster; JoiPlay varies.

## What the T6 suite proves about search quality (not speed)

- Expectimax decomposition: at depth 1 the search value equals
  Σ pᵢ·eval(childᵢ) over the same enumerated outcomes exactly.
- ε-pruning: |value(ε=0) − value(ε=0.45)| ≤ 0.45 and prunes actually fire.
- Determinism: identical config → identical value and action.
- Replacement enumeration: value becomes party-order independent; the
  adversary assumes the foe's best counter (Tyranitar over Blissey).
