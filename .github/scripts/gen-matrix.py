#!/usr/bin/env python3
"""gen-matrix.py [--only-blocking] [--series S] — emit a GitHub Actions matrix
(JSON on stdout) of {series,target,blocking} combos from series.yaml."""
import json, sys, yaml, pathlib, argparse

ap = argparse.ArgumentParser()
ap.add_argument("--only-blocking", action="store_true")
ap.add_argument("--series")
a = ap.parse_args()

root = pathlib.Path(__file__).resolve().parents[2]
doc = yaml.safe_load((root / "series.yaml").read_text())
inc = []
for s, cfg in doc["build"].items():
    if a.series and s != a.series:
        continue
    blocking = cfg.get("blocking", True)
    if a.only_blocking and not blocking:
        continue
    for t in cfg["targets"]:
        inc.append({"series": s, "target": t, "blocking": blocking})
print(json.dumps({"include": inc}))
