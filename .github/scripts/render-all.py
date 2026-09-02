#!/usr/bin/env python3
"""render-all.py [--flavour dkms] — render every (series, target) in the matrix
into /tmp/render-check/ to prove the templates + drivers.yaml are consistent.
Used by the static gate; not a build."""
import json, subprocess, sys, pathlib

flavour = "dkms"
if "--flavour" in sys.argv:
    flavour = sys.argv[sys.argv.index("--flavour") + 1]

root = pathlib.Path(__file__).resolve().parents[2]
m = json.loads(subprocess.check_output(
    [sys.executable, str(root / ".github/scripts/gen-matrix.py")]))

fail = 0
for c in m["include"]:
    out = f"/tmp/render-check/{c['series']}/{c['target']}"
    r = subprocess.run(
        [sys.executable, str(root / "common/scripts/render-debian.py"),
         "--series", c["series"], "--target", c["target"],
         "--flavour", flavour, "--out", out])
    if r.returncode != 0:
        print(f"FAIL render {c['series']}/{c['target']}")
        fail = 1

sys.exit(fail)
