#!/usr/bin/env bash
# run-all.sh <series> <target> [--deps]
# Full no-GPU gate for one combo. Exit non-zero only if a BLOCKING stage fails.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

if [ "${1:-}" = "--deps" ]; then
  sudo apt-get update
  sudo apt-get install -y sbuild reprotest diffoscope autopkgtest \
    qemu-system-x86 qemu-utils cloud-image-utils mmdebstrap podman shellcheck \
    lintian devscripts blhc python3-yaml
  exit 0
fi

series="${1:?series}"; target="${2:?target}"
blocking=1; is_blocking "$series" || blocking=0
info "combo: $series / $target  (blocking=$blocking)"

rc=0
stage() {
  local name="$1"; shift
  info ">>> stage: $name"
  if "$@"; then ok "stage $name"; else
    if [ "$blocking" = 1 ]; then no "stage $name (BLOCKING)"; rc=1
    else skip "stage $name (non-blocking series)"; fi
  fi
}

stage static      "$REPO_ROOT/.github/scripts/static-checks.sh" "$series" "$target"
stage build       "$REPO_ROOT/.github/scripts/sbuild-wrap.sh"   "$series" "$target"
stage reprotest   "$REPO_ROOT/.github/scripts/reprotest-wrap.sh" "$series" "$target"
stage dkms-matrix "$TESTS_ROOT/dkms-matrix/run.sh"              "$series" "$target"
stage autopkgtest "$TESTS_ROOT/autopkgtest/run.sh"             "$series" "$target"
stage qemu        "$TESTS_ROOT/qemu/run.sh"                    "$series" "$target"

echo
if [ "$rc" = 0 ]; then ok "ALL BLOCKING STAGES GREEN — $series/$target is publishable"
else no "release gate CLOSED for $series/$target"; fi
exit $rc
