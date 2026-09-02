#!/usr/bin/env bash
# reprotest-wrap.sh <series> <target> — build twice with varied environment and
# diffoscope the .debs. Any difference fails the release gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILDDIR="${BUILDDIR:-$ROOT/../build}"
series="${1:?}"; target="${2:?}"
tree="$ROOT/packaging/$series/$target"
[ -d "$tree/debian" ] || { echo "render first"; exit 1; }

command -v reprotest >/dev/null || { echo "reprotest not installed"; exit 1; }

cd "$tree"
# Vary everything reprotest safely can; keep build path constant (NVIDIA blob
# Makefiles are not path-agnostic) and user_group constant (fakeroot quirks).
reprotest \
  --vary=-user_group \
  --vary=-build_path \
  --vary=+kernel,+time,+timezone,+locales,+env,+umask,+aslr \
  --store-dir="$BUILDDIR/reprotest-$series-$target" \
  "dpkg-buildpackage --no-sign -b" \
  "../*.deb"
echo "REPROTEST: identical"
