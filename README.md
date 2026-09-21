# Pokémon Añil/Azul Competitive Coach

Engineering workspace for the **Competitive Coach Engine 2.0** used with the user's Pokémon Añil/Azul build.

The goal is a battle recommendation engine that models complete turns, switching, priority/speed, contextual damage/accuracy, probabilistic outcomes and 6v6 strategy while keeping the rest of the game untouched.

## Start here

Agent/AI contributors: read **[AGENT_PROMPT.md](AGENT_PROMPT.md)** before modifying code. Then audit the actual source and produce **AUDIT.md** before the Engine 2.0 refactor.

## Repository layout

- `AGENT_PROMPT.md` — engineering handoff and non-negotiable requirements.
- `src/extracted_scripts/` — Ruby scripts extracted from the current `Scripts.rxdata`, preserving load order.
- `data/` — game data needed to map moves/items/abilities/species.
- `baseline/Scripts.rxdata` — supplied binary baseline/source of truth (never modified).
- `game/Scripts.rxdata` — **rebuilt data file with Coach Engine 2.0** (616 original sections byte-identical + one new final section). Drop-in replacement; rebuild with `python3 tools/build_engine2_rxdata.py`.
- `SCRIPT_MANIFEST.tsv` — script index/name/file mapping.
- `engine2/` — Engine 2.0 sources (twin battle, turn driver, action space, evaluator, search, in-game integration).
- `tests/headless/` — regression harness running the REAL engine + PBS data headless (see AUDIT.md §6 for results): `run_engine2.rb` is the 64-check acceptance suite, `run_audit.rb` runs `t7_audit.rb` (24 post-merge audit regressions, AUDIT.md §8).
- `tools/` — `rxdata.py` (Marshal reader/writer), `build_engine2_rxdata.py` (verified build), `rubyrun.py` (wasm runner).
- `AUDIT.md` / `BENCHMARKS.md` / `CHANGELOG.md` — verification record, measured numbers, and change log.

## Verifying the build

```
# rebuild + verify the rxdata (byte-identity of originals, new section last)
python3 tools/build_engine2_rxdata.py

# run the full regression suite (needs the wasm ruby toolchain; see AUDIT.md)
# args: <host dir> <ruby+stdlib.wasm> file <scripts...>
python3 tools/rubyrun.py . path/to/package/dist/ruby+stdlib.wasm file \
    tests/headless/boot.rb tests/headless/run_engine2.rb

# post-merge audit regressions (T7)
python3 tools/rubyrun.py . path/to/package/dist/ruby+stdlib.wasm file \
    tests/headless/boot.rb tests/headless/run_audit.rb
```

The toolchain is `@ruby/3.3-wasm-wasi` (npm) plus `pip install wasmtime`;
`<host dir>` is the directory the scripts are resolved against.

Current status: T1 10/10, T2 (the six mandatory scenarios) 17/17, T3 8/8,
T4 8/8, T6 (exact chance / adaptive pruning / replacements / beliefs) 21/21,
shipped-rxdata smoke PASS — 64 checks + smoke, all against the real engine
with real data — plus T7 24/24, the post-merge audit regressions
(AUDIT.md §8: chance-branch identification and its outcome cap, a choice
aliasing bug that silently dropped game-AI and multi-turn-locked actions,
snapshot twin protections, transposition-key collisions, foe reply ordering,
and the BattleSync isolation gate). Chance events are enumerated with
probabilities measured against the engine itself (accuracy thresholds proven
differentially by pinned rolls, crit rates from the engine's own rolls, damage
bands exact per roll); remaining approximations are explicit and listed in
AUDIT.md §4/§7 (one path-altering branch per round, mid-band damage
quadrature at :coarse, capped enumerations folded into one probe-state
outcome, uncalibrated evaluator, native performance unmeasured).

**Important:** the supplied baseline contains Coach code through **v27**. Do not assume a conversational v28 exists unless it is present in the repository.

## Safety / multiplayer boundary

Production Coach logic may use only information the normal client legitimately receives through battle state, Team Preview or BattleSync. This project is not for bypassing authentication, anti-cheat/debug checks, server authorization, hidden routes, or private opponent data.

Inside an active BattleSync co-op context, Engine 2.0 REFUSES to snapshot the battle (`TwinIsolationError` → the HUD falls back to the pre-2.0 v27 chain) rather than simulate rounds that could act on the peer connection: the rework's network wrappers sit on battle phases a twin cannot detach. `CoachEngine2.allow_sync_twins = true` overrides this only after it has been verified on the real client.

## Development rule

Do not keep stacking Pokémon-specific monkey-patches. The target is one coherent Engine 2.0 with a single authoritative `TurnResolver`.