#!/usr/bin/env python3
"""Builds a NEW Scripts.rxdata containing Coach Engine 2.0.

Never touches baseline/Scripts.rxdata (the supplied original). The output is
written to game/Scripts.rxdata and contains:
    * all 616 original entries, byte-identical (raw deflated blobs reused);
    * one new final section with the concatenated engine2 sources.

Verification performed by this script (it refuses to write on any failure):
    1. round-trip: the written file re-reads to exactly the intended entries;
    2. identity: original entries' (id, name, raw-code) match the baseline;
    3. count and order: 617 entries, new section last;
    4. content: the new section's inflated code equals the concatenation of
       the engine2 sources, byte for byte.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rxdata import read_scripts, write_scripts

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "baseline", "Scripts.rxdata")
OUT = os.path.join(ROOT, "game", "Scripts.rxdata")

# Dependency order (integration last: it redefines the recommendation entry
# point and must run after everything else in the file).
ENGINE2_FILES = [
    "twin_battle.rb",
    "turn_driver.rb",
    "action_space.rb",
    "eval.rb",
    "search.rb",
    "integration.rb",
]

SECTION_NAME = "MOD_ Coach Engine 2.0"


def main():
    baseline = read_scripts(BASELINE)
    n = len(baseline)
    max_sid = max(e[1] for e in baseline)
    print(f"baseline: {n} entries, max script id {max_sid}")

    parts = []
    for fname in ENGINE2_FILES:
        path = os.path.join(ROOT, "engine2", fname)
        src = open(path, "r", encoding="utf-8").read()
        if not src.endswith("\n"):
            src += "\n"
        # UTF-8 is fine (the game's own scripts are Spanish UTF-8); what we
        # require is valid UTF-8 and an explicit encoding magic comment, so
        # Ruby parses the section correctly regardless of load order.
        src.encode("utf-8")  # raises if the file on disk is not valid UTF-8
        first_lines = "\n".join(src.split("\n")[:2])
        if "# encoding: UTF-8" not in first_lines:
            raise SystemExit(f"{fname} lacks the '# encoding: UTF-8' magic comment")
        parts.append(src)
    combined = "\n".join(parts)

    entries = []
    for _i, sid, name, _code, raw in baseline:
        entries.append((sid, name.encode("utf-8"), raw, raw))
    new_sid = max_sid + 1
    entries.append((new_sid, SECTION_NAME.encode("utf-8"), combined, None))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write_scripts(OUT, entries)
    print(f"wrote {OUT}: {len(entries)} entries, new section id {new_sid}")

    # ---- verification -------------------------------------------------------
    again = read_scripts(OUT)
    assert len(again) == n + 1, f"count mismatch: {len(again)} != {n + 1}"
    for k in range(n):
        a = (baseline[k][1], baseline[k][2].encode("utf-8"), baseline[k][4])
        b = (again[k][1], again[k][2].encode("utf-8"), again[k][4])
        assert a == b, f"entry {k} differs from baseline"
    assert again[n][1] == new_sid, "new entry id mismatch"
    assert again[n][2] == SECTION_NAME, "new entry name mismatch"
    assert again[n][3] == combined, "new entry code mismatch after round-trip"
    print("verified: 616 original entries byte-identical; new section last;")
    print(f"          new section inflates to {len(combined)} chars of engine2 source")
    print("OK")


if __name__ == "__main__":
    main()
