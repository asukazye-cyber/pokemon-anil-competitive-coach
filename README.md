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
- `tests/headless/` — regression harness running the REAL engine + PBS data headless (see AUDIT.md §6 for results).
- `tools/` — `rxdata.py` (Marshal reader/writer), `build_engine2_rxdata.py` (verified build), `rubyrun.py` (wasm runner).
- `AUDIT.md` / `BENCHMARKS.md` / `CHANGELOG.md` — verification record, measured numbers, and change log.

## Verifying the build

```
# rebuild + verify the rxdata (byte-identity of originals, new section last)
python3 tools/build_engine2_rxdata.py

# run the full regression suite (needs the wasm ruby toolchain; see AUDIT.md)
python3 tools/rubyrun.py package/dist/ruby+stdlib.wasm file tests/headless/boot.rb tests/headless/run_engine2.rb
```

Current status: T1 10/10, T2 (the six mandatory scenarios) 17/17, T3 8/8,
T4 8/8, shipped-rxdata smoke PASS. Scope and known limitations are listed in
AUDIT.md §4/§7 — most importantly: chance nodes are currently collapsed by
a median roll policy (values are estimates, not exact probabilities), and
native in-game performance has not been measured in this environment.

**Important:** the supplied baseline contains Coach code through **v27**. Do not assume a conversational v28 exists unless it is present in the repository.

## Safety / multiplayer boundary

Production Coach logic may use only information the normal client legitimately receives through battle state, Team Preview or BattleSync. This project is not for bypassing authentication, anti-cheat/debug checks, server authorization, hidden routes, or private opponent data.

## Development rule

Do not keep stacking Pokémon-specific monkey-patches. The target is one coherent Engine 2.0 with a single authoritative `TurnResolver`.