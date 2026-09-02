#!/usr/bin/env bash
# Shared test helpers. Source, don't run.
set -euo pipefail
TESTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"
BUILDDIR="${BUILDDIR:-$REPO_ROOT/../build}"

pass=0; fail=0; skip=0
ok()   { printf '\033[32mPASS\033[0m %s\n' "$*"; pass=$((pass+1)); }
no()   { printf '\033[31mFAIL\033[0m %s\n' "$*"; fail=$((fail+1)); }
skip() { printf '\033[33mSKIP\033[0m %s\n' "$*"; skip=$((skip+1)); }
info() { printf '\033[36m::\033[0m %s\n' "$*"; }

assert()      { if eval "$1"; then ok "${2:-$1}"; else no "${2:-$1}"; fi; }
assert_file() { [ -e "$1" ] && ok "exists: $1" || no "missing: $1"; }

summary() {
  echo "-----"
  echo "pass=$pass fail=$fail skip=$skip"
  [ "$fail" -eq 0 ]
}

# is this (series,target) blocking? reads ../series.yaml
is_blocking() {
  python3 - "$REPO_ROOT/series.yaml" "$1" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
b = doc["build"].get(sys.argv[2], {}).get("blocking", True)
sys.exit(0 if b else 1)
PY
}
