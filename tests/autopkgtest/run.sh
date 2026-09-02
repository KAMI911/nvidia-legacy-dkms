#!/usr/bin/env bash
# autopkgtest/run.sh <series> <target>
# Runs the archive autopkgtests against the freshly built .debs in a container.
set -uo pipefail
. "$(dirname "$0")/../lib.sh"
series="${1:?}"; target="${2:?}"

declare -A img=(
  [debian11]=debian:11 [debian12]=debian:12 [debian13]=debian:trixie
  [ubuntu2004]=ubuntu:20.04 [ubuntu2204]=ubuntu:22.04 [ubuntu2404]=ubuntu:24.04)
base="${img[$target]:?}"
command -v podman >/dev/null && OCI=podman || OCI=docker

cid="apt-$series-$target"
$OCI rm -f "$cid" >/dev/null 2>&1 || true
set +e
$OCI run --name "$cid" -v "$BUILDDIR":/build:ro -v "$(dirname "$0")":/t:ro \
  -e SERIES="$series" "$base" bash -c '
    set -e; export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq /build/*.deb 2>/dev/null || { dpkg -i /build/*.deb; apt-get -f install -y -qq; }
    fail=0
    for t in install-purge file-conflicts xorg-dummy; do
      echo "===== $t ====="
      bash /t/$t.sh "$SERIES" || fail=1
    done
    exit $fail
  '
rc=$?
set -e
$OCI rm -f "$cid" >/dev/null 2>&1 || true
[ $rc -eq 0 ] && ok "autopkgtest $target" || no "autopkgtest $target"
summary
