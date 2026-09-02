#!/usr/bin/env python3
"""fwd-series.py [<series>] — emit `list=[...]` (GITHUB_OUTPUT) of series for the
forward-port sweep: the given one, or all experimental/best-effort feasible ones."""
import sys, json, yaml, pathlib

one = sys.argv[1].strip() if len(sys.argv) > 1 else ""
root = pathlib.Path(__file__).resolve().parents[2]
d = yaml.safe_load((root / "common" / "drivers.yaml").read_text())["series"]

if one:
    sel = [one]
else:
    sel = [k for k, v in d.items()
           if v.get("modern_feasible", True)
           and v.get("status") in ("experimental", "best-effort")]

print("list=" + json.dumps(sel))
