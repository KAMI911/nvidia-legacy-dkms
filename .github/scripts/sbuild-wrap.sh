#!/usr/bin/env bash
# sbuild-wrap.sh <series> <target> — build the source package in a clean chroot
# for every arch that series/target needs. Captures .buildinfo. blhc on the log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COMMON="$ROOT/common"
BUILDDIR="${BUILDDIR:-$ROOT/../build}"
series="${1:?}"; target="${2:?}"

declare -A codename=(
  [debian11]=bullseye [debian12]=bookworm [debian13]=trixie
  [ubuntu2004]=focal [ubuntu2204]=jammy [ubuntu2404]=noble)
cn="${codename[$target]:?unknown target}"

# arches for this (series,target) from series.yaml
mapfile -t arches < <(python3 - "$ROOT/series.yaml" "$series" "$target" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1])); s, t = sys.argv[2], sys.argv[3]
cfg = doc["build"][s]
fam = "debian" if t.startswith("debian") else "ubuntu"
for a in cfg["archs"].get(fam, []):
    # i386 kernel module only where the distro ships an i386 kernel
    if a == "i386" and fam == "ubuntu":
        continue
    print(a)
PY
)
[ "${#arches[@]}" -gt 0 ] && echo "arches: ${arches[*]}" || { echo "nothing to build"; exit 0; }

mkdir -p "$BUILDDIR"
"$COMMON/scripts/verify-run.sh" "$series"
"$COMMON/scripts/assemble-source.sh" "$series" "$BUILDDIR"

tree="$ROOT/packaging/$series/$target"
python3 "$COMMON/scripts/render-debian.py" --series "$series" --target "$target" --flavour dkms --out "$tree"
( cd "$BUILDDIR" && dpkg-source --no-check -b "$tree" )
dsc="$(ls -t "$BUILDDIR"/nvidia-legacy-"$series"_*.dsc | head -1)"

for arch in "${arches[@]}"; do
  echo "==== sbuild $series/$cn/$arch ===="
  SOURCE_DATE_EPOCH="$(dpkg-parsechangelog -l"$tree/debian/changelog" -STimestamp)" \
  sbuild --dist="$cn" --arch="$arch" --no-arch-all \
    ${arch:+--extra-repository="deb [trusted=yes] file://$BUILDDIR ./"} \
    --build-dir="$BUILDDIR" --stats-dir="$BUILDDIR/stats" \
    --dpkg-source-opts="--no-check" \
    "$dsc" 2>&1 | tee "$BUILDDIR/build-$series-$cn-$arch.log"

  # hardening check on the actual build log
  if command -v blhc >/dev/null; then
    blhc --all "$BUILDDIR/build-$series-$cn-$arch.log" && echo "blhc: clean" \
      || { echo "blhc: hardening issues"; exit 1; }
  fi
done
ls -l "$BUILDDIR"/*.buildinfo 2>/dev/null || echo "WARN: no .buildinfo produced"
