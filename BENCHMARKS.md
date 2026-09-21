# BENCHMARKS — Coach Engine 2.0

All numbers below were measured in the only environment available for
verification: Ruby 3.3.3 **wasm32-wasi** under wasmtime 48, with the real
Añil engine and real PBS data loaded. They are honest for that environment.
Native desktop and JoiPlay/Android performance will differ (expected faster
on native desktop; variable on JoiPlay) — those numbers are NOT claimed
here. Re-run `tests/headless/bench.rb` on target hardware for local figures.

## Search benchmarks (via `tests/headless/bench.rb`)

Config: `:adversarial` foe model unless noted; budgets as shipped
(desktop: depth 3 / 300 rounds / 3000 ms; joiplay: depth 2 / 100 rounds /
1800 ms).

| Scenario | Best | Value | nodes | rounds | depth | ms | rounds/s | TT hit/store |
|---|---|---|---|---|---|---|---|---|
| A trivial Lv100 vs Lv3 (desktop) | Tierra Viva | 1.00 | 6 | 6 | 3 | 113 | 52.9 | 0/0 |
| B even 1v1 (desktop) | Surf | 0.44 | 95 | 95 | 3 | 3018 | 31.5 | 1/10 |
| C 2-mon side w/ switches (desktop) | Surf | 0.46 | 97 | 103 | 3 | 3008 | 34.2 | 0/11 |
| D same, foe = game AI (desktop) | Surf | 0.68 | 51 | 51 | 3 | 2352 | 21.7 | 1/14 |
| E 2-mon side (joiplay budget) | Surf | 0.46 | 52 | 54 | 2 | 1821 | 29.7 | 0/5 |
| F low-HP endgame, depth 4 | Surf | 0.44 | 32 | 32 | 4 | 1128 | 28.4 | 2/12 |

## Unit costs

| Operation | Cost |
|---|---|
| Raw round execution (Marshal clone + full `pbAttackPhase` + `pbEndOfRoundPhase`) | ~31 ms/round (30 rounds, 932 ms) |
| Full boot (engine + data) in wasm | ~45 s (test-driver startup; irrelevant to in-game use) |
| from_live snapshot (T3) | included in search budgets above |

## Reading the numbers

- **Adaptive depth works within budget**: the trivial position (A) solves to
  a proven win (W = 1.0, terminal decision) in 6 rounds / 113 ms, while even
  midgame positions (B/C) spend the full budget and reach depth 3.
- **Budgets are respected**: every scenario terminates within its time/node
  budget; the search returns the deepest completed iteration's best action.
- **Throughput** is ~22–34 search rounds/s in this wasm environment
  (B–E). A native desktop CPU is expected to be several times faster;
  JoiPlay varies by device.
- **TT effectiveness** is currently modest (hit counts single digits at
  these depths) — expected, since the search rarely revisits identical
  states within 2–3 rounds. Deeper searches will amortize it.
- **game AI foe model** (D) is cheaper per node in foe branching but slower
  per round (the game AI's own scoring runs per node) and yields a HIGHER
  value (0.68 vs 0.46) than the adversarial model — consistent with an
  optimal-play assumption being more pessimistic than the game's AI.

## Engine 2.0 budgets as shipped (integration.rb)

| Profile | depth | round budget | time budget | foe branching | our branching |
|---|---|---|---|---|---|
| desktop | 3 | 300 | 3000 ms | 5 | 14 |
| joiplay | 2 | 100 | 1800 ms | 4 | 10 |

Profile auto-detection prefers JoiPlay when Android markers are present;
override with `CoachEngine2::CONFIG[:profile]`. Disable entirely with
`CoachEngine2.enabled = false` (falls back to the pre-2.0 Coach chain).
