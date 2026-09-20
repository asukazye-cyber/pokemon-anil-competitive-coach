# Pokémon Añil/Azul Competitive Coach

Engineering workspace for the **Competitive Coach Engine 2.0** used with the user's Pokémon Añil/Azul build.

The goal is a battle recommendation engine that models complete turns, switching, priority/speed, contextual damage/accuracy, probabilistic outcomes and 6v6 strategy while keeping the rest of the game untouched.

## Start here

Agent/AI contributors: read **[AGENT_PROMPT.md](AGENT_PROMPT.md)** before modifying code. Then audit the actual source and produce **AUDIT.md** before the Engine 2.0 refactor.

## Repository layout

- `AGENT_PROMPT.md` — engineering handoff and non-negotiable requirements.
- `src/extracted_scripts/` — Ruby scripts extracted from the current `Scripts.rxdata`, preserving load order.
- `data/` — game data needed to map moves/items/abilities/species.
- `baseline/Scripts.rxdata` — supplied binary baseline/source of truth.
- `SCRIPT_MANIFEST.tsv` — script index/name/file mapping.
- `tests/` — regression harnesses for real Coach failures.
- `docs/` — audit, architecture and benchmark notes.

**Important:** the supplied baseline contains Coach code through **v27**. Do not assume a conversational v28 exists unless it is present in the repository.

## Safety / multiplayer boundary

Production Coach logic may use only information the normal client legitimately receives through battle state, Team Preview or BattleSync. This project is not for bypassing authentication, anti-cheat/debug checks, server authorization, hidden routes, or private opponent data.

## Development rule

Do not keep stacking Pokémon-specific monkey-patches. The target is one coherent Engine 2.0 with a single authoritative `TurnResolver`.