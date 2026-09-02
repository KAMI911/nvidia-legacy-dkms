#!/usr/bin/env python3
"""release-gate.py <artifacts-dir>

Reads every *-verdicts.json under <artifacts-dir> (one per test stage, produced
by the reusable workflows) and prints `SERIES TARGET` for each combo that is
`pass` in ALL blocking stages. Non-blocking series never appear here (they are
published separately, out of the gate).

verdicts.json shape: { "stage": "dkms", "results": { "390xx/debian13": "pass", ... } }
"""
import json, sys, pathlib, collections

art = pathlib.Path(sys.argv[1])
REQUIRED = {"static", "build", "reprotest", "dkms", "autopkgtest", "qemu"}
seen = collections.defaultdict(dict)

for f in art.rglob("*-verdicts.json"):
    d = json.loads(f.read_text())
    for combo, verdict in d.get("results", {}).items():
        seen[combo][d["stage"]] = verdict

for combo, stages in sorted(seen.items()):
    if not REQUIRED.issubset(stages):
        print(f"# {combo}: missing stages {REQUIRED - set(stages)}", file=sys.stderr)
        continue
    if all(stages[s] == "pass" for s in REQUIRED):
        series, target = combo.split("/")
        print(f"{series} {target}")
    else:
        bad = {s: v for s, v in stages.items() if v != "pass"}
        print(f"# {combo}: not green -> {bad}", file=sys.stderr)
