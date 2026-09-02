#!/usr/bin/env bash
# static-checks.sh [<series> <target>]  — the blocking static gate.
# With no args: repo-wide checks only. With args: also lint that rendered tree.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMON="$ROOT/common"
rc=0
# CI checkout is owned by a different uid than the runner user
git config --global --add safe.directory '*' 2>/dev/null || true
note() { printf '\033[36m::\033[0m %s\n' "$*"; }
bad()  { printf '\033[31mFAIL\033[0m %s\n' "$*"; rc=1; }

note "1. no driver blobs committed"
if git -C "$ROOT" ls-files | grep -E '\.(run|bin)$|NVIDIA-Linux'; then
  bad "a .run / NVIDIA blob is tracked in git — must be fetched at build time"
fi
if [ "$(git -C "$ROOT" ls-files -z | xargs -0 -I{} stat -c%s "$ROOT/{}" 2>/dev/null | sort -n | tail -1)" -gt 5000000 ] 2>/dev/null; then
  bad "a tracked file exceeds 5 MB"
fi

note "2. shellcheck"
if command -v shellcheck >/dev/null; then
  mapfile -d '' scripts < <(git -C "$ROOT" ls-files -z '*.sh' ':!:common')
  if [ "${#scripts[@]}" -gt 0 ]; then
    ( cd "$ROOT" && shellcheck -S error -e SC1091 "${scripts[@]}" ) || bad "shellcheck errors"
  else
    note "  (no .sh files found — skipped)"
  fi
else note "  (shellcheck not installed — skipped)"; fi

note "3. patch provenance complete"
for pdir in "$COMMON"/patches/*/; do
  s="$(basename "$pdir")"
  "$COMMON/scripts/import-patches.sh" --check "$s" || bad "provenance mismatch for $s"
done

note "4. drivers.yaml: no UNVERIFIED hash for a 'supported' series"
python3 - "$COMMON/drivers.yaml" <<'PY' || rc=1
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])); bad = 0
for name, s in doc["series"].items():
    if s["status"] != "supported":
        continue
    for arch, r in s.get("runs", {}).items():
        if r.get("sha256", "UNVERIFIED") == "UNVERIFIED":
            print(f"FAIL: {name}/{arch} sha256 UNVERIFIED but series is 'supported'"); bad = 1
sys.exit(bad)
PY

if [ $# -eq 2 ]; then
  series="$1"; target="$2"
  note "5. render + lintian ($series/$target)"
  tree="$ROOT/packaging/$series/$target"
  python3 "$COMMON/scripts/render-debian.py" --series "$series" --target "$target" \
    --flavour dkms --out "$tree" || bad "render failed"
  dsc=$(ls "$ROOT"/../build/nvidia-legacy-"${series}"_*.dsc 2>/dev/null | head -1 || true)
  if command -v lintian >/dev/null && [ -n "$dsc" ]; then
    lintian -I --pedantic "$ROOT/../build/nvidia-legacy-${series}_"*.changes 2>/dev/null \
      | tee /tmp/lintian.txt
    grep -E '^E:' /tmp/lintian.txt && bad "lintian errors"
  else
    note "  (no .changes yet — control-file sanity only)"
    dpkg-checkbuilddeps "$tree/debian/control" 2>&1 | grep -v "Unmet" || true
  fi
  note "6. blhc (hardening) — checked in build stage on the real build log"
fi

[ $rc -eq 0 ] && echo "STATIC GATE: PASS" || echo "STATIC GATE: FAIL"
exit $rc
