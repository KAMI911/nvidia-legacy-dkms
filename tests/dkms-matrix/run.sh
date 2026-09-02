#!/usr/bin/env bash
# dkms-matrix/run.sh <series> <target> [--kernel <abi>]
#
# For each kernel in kernels.yaml[<target>]: spin a throwaway container of the
# target distro, install the pinned linux-headers + the built
# nvidia-legacy-<series>-kernel-dkms .deb, run `dkms build`, and assert:
#   * every expected .ko is produced
#   * `modinfo` reports the right vermagic and a non-empty srcversion
#   * `depmod -n` shows no unresolved symbols for the nvidia modules
# No GPU required — we never insmod here (that's qemu/run.sh).
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
series="${1:?series}"; target="${2:?target}"; only="${4:-}"

command -v podman >/dev/null && OCI=podman || OCI=docker
declare -A img=(
  [debian11]=debian:11 [debian12]=debian:12 [debian13]=debian:trixie
  [ubuntu2004]=ubuntu:20.04 [ubuntu2204]=ubuntu:22.04 [ubuntu2404]=ubuntu:24.04)
base="${img[$target]:?unknown target}"

deb="$(ls "$BUILDDIR"/nvidia-legacy-"$series"-kernel-dkms_*_all.deb \
        "$BUILDDIR"/nvidia-legacy-"$series"-kernel-dkms_*.deb 2>/dev/null | head -1)" \
  || { no "no kernel-dkms .deb in $BUILDDIR"; summary; exit 1; }

mapfile -t rows < <(python3 - "$(dirname "$0")/kernels.yaml" "$target" "$only" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])); tgt, only = sys.argv[2], sys.argv[3]
for e in doc.get(tgt, []):
    if only and e["abi"] != only: continue
    print(f'{e["abi"]}\t{e["pkg"]}\t{e.get("ver","*")}\t{e["fetch"]}\t{e.get("blocking",True)}\t{e.get("arch","amd64")}')
PY
)
[ "${#rows[@]}" -gt 0 ] || { no "no kernels listed for $target"; summary; exit 1; }

for row in "${rows[@]}"; do
  IFS=$'\t' read -r abi pkg ver fetch blocking arch <<<"$row"
  info "=== $target / $abi ($pkg, fetch=$fetch, arch=$arch) ==="
  cid="dkmstest-$series-$target-${abi//[^a-zA-Z0-9]/_}"
  $OCI rm -f "$cid" >/dev/null 2>&1 || true
  set +e
  $OCI run --name "$cid" -v "$BUILDDIR":/build:ro -v "$(dirname "$0")":/t:ro \
    -e SERIES="$series" -e KABI="$abi" -e KPKG="$pkg" -e KFETCH="$fetch" -e KARCH="$arch" \
    -e DEB="/build/$(basename "$deb")" \
    "$base" /t/_in-container.sh
  rc=$?
  set -e
  $OCI rm -f "$cid" >/dev/null 2>&1 || true
  if [ $rc -eq 0 ]; then ok "$abi built + verified"
  elif [ $rc -eq 77 ]; then skip "$abi (headers unavailable)"
  elif [ "$blocking" = "False" ] || [ "$blocking" = "false" ]; then skip "$abi FAILED but non-blocking"
  else no "$abi build/verify failed (rc=$rc)"
  fi
done
summary
