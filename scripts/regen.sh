#!/usr/bin/env bash
# regen.sh — (re)render packaging/<series>/<target>/debian/ for every combo in
# series.yaml, using the templates + drivers.yaml from the common/ submodule.
# Series without a template dir yet (see common/debian-template/) are skipped
# with a warning — that is expected while a series is still being brought up.
# Run after `git submodule update --remote common`. Commit the result.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMON="$ROOT/common"
RENDER="$COMMON/scripts/render-debian.py"
[ -x "$RENDER" ] || { echo "common/ submodule not initialised"; exit 1; }

FLAVOUR="$(python3 -c 'import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))["flavour"])' "$ROOT/series.yaml")"
rc=0; done=0; skipped=0

while read -r series target; do
  if [ ! -d "$COMMON/debian-template/$series/debian" ]; then
    echo ":: skip $series/$target (no template yet)"; skipped=$((skipped+1)); continue
  fi
  echo ":: render $series / $target"
  if python3 "$RENDER" --series "$series" --target "$target" --flavour "$FLAVOUR" \
       --out "$ROOT/packaging/$series/$target"; then
    done=$((done+1))
  else
    echo "   !! render failed for $series/$target"; rc=1
  fi
done < <(python3 - "$ROOT/series.yaml" <<'PY'
import yaml, sys
doc = yaml.safe_load(open(sys.argv[1]))
for s, cfg in doc["build"].items():
    for t in cfg["targets"]:
        print(s, t)
PY
)

echo "rendered=$done skipped=$skipped"

# xorg-server-legacy-nvidia-<abi> for every series in the build set that needs it
if [ -f "$COMMON/scripts/render-xserver.py" ]; then
  for abi in $(python3 - "$ROOT/series.yaml" "$COMMON/drivers.yaml" <<'PY'
import sys, yaml
build = yaml.safe_load(open(sys.argv[1]))["build"]
series = yaml.safe_load(open(sys.argv[2]))["series"]
abis = set()
for s in build:
    e = series.get(s, {})
    if e.get("x_via") == "legacy-xserver":
        abis.add(str(e.get("x_driver_max_abi", e["xorg_abi_max"])))
print(" ".join(sorted(abis, key=int)))
PY
  ); do
    echo ":: render xorg-server-legacy-nvidia-$abi"
    python3 "$COMMON/scripts/render-xserver.py" --abi "$abi" \
      --out "$ROOT/packaging/xserver-$abi" || rc=1
  done
fi

echo "Review 'git status' under packaging/ and commit."
exit $rc
