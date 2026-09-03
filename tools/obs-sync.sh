#!/usr/bin/env bash
# obs-sync.sh — push CI-rendered source packages to OBS.
#
#   OBS_PROJECT=home:<login>:nvidia-legacy:dkms  tools/obs-sync.sh <series> [--dry-run]
#   tools/obs-sync.sh <series> --project home:<login>:nvidia-legacy:dkms [--dry-run]
#
# Expects, in $BUILDDIR (default ../build):
#   nvidia-legacy-<series>_<ver>-*.dsc              one per target
#   nvidia-legacy-<series>_<ver>.orig.tar.xz        + optional -i386
#   nvidia-legacy-<series>_<ver>-*.debian.tar.xz
#
# Writes alternative .dsc names (nvidia-legacy-<series>-<OBS_repo>.dsc) and a
# _multibuild listing only the targets actually present, so one OBS package
# builds every target it has sources for. The package is created (build on,
# publish off) if it does not exist yet.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILDDIR="${BUILDDIR:-$ROOT/../build}"
PROJECT="${OBS_PROJECT:-home:KAMI911:nvidia-legacy:dkms}"
DRY=0
series="${1:?usage: obs-sync.sh <series> [--project P] [--dry-run]}"; shift || true
while [ $# -gt 0 ]; do case "$1" in
  --project) PROJECT="$2"; shift ;; --dry-run) DRY=1 ;; *) echo "unknown arg: $1" >&2; exit 2 ;;
esac; shift; done
command -v osc >/dev/null || { echo "osc not installed"; exit 1; }

pkg="nvidia-legacy-$series"
ver="$(sed -n 's/^Version: //p' "$BUILDDIR/${pkg}_"*-*.dsc | sed 's/-[^-]*$//; s/.*://' | head -1)"
[ -n "$ver" ] || { echo "no .dsc for $pkg in $BUILDDIR"; exit 1; }

# --- ensure the OBS package exists (build on / publish off) ------------------
if ! osc api "/source/$PROJECT/$pkg/_meta" >/dev/null 2>&1; then
  echo ":: creating $PROJECT/$pkg"
  meta="$(OBS_PROJECT="$PROJECT" "$ROOT/_obs/render.sh" pkg "$series" "$ver")"
  [ "$DRY" = 1 ] || osc api -X PUT "/source/$PROJECT/$pkg/_meta" --data "$meta" >/dev/null
fi

wd="$(mktemp -d)"; trap 'rm -rf "$wd"' EXIT
# plain `osc co PROJECT PKG` creates ./PROJECT/PKG/ with the .osc/ metadata that
# `osc addremove` / `osc ci` need.
( cd "$wd" && osc co "$PROJECT" "$pkg" ) || { echo "osc co failed for $PROJECT/$pkg"; exit 1; }
pdir="$wd/$PROJECT/$pkg"
test -d "$pdir/.osc" || { echo "no .osc working copy at $pdir"; exit 1; }

cp "$BUILDDIR/${pkg}_"*.orig*.tar.* "$pdir/"

targets=()
for dsc in "$BUILDDIR/${pkg}_"*-*.dsc; do
  [ -e "$dsc" ] || continue
  base="$(basename "$dsc")"
  suffix="$(sed -n 's/.*~\([a-z]*\)[0-9]*\.dsc/\1/p' <<<"$base")"
  case "$suffix" in
    trixie)   repo=Debian_13     ;; bookworm) repo=Debian_12     ;; bullseye) repo=Debian_11 ;;
    resolute) repo=xUbuntu_26.04 ;; noble)    repo=xUbuntu_24.04 ;;
    jammy)    repo=xUbuntu_22.04 ;; focal)    repo=xUbuntu_20.04 ;;
    *) echo "cannot map $base"; continue ;;
  esac
  cp "$dsc" "$pdir/${pkg}-${repo}.dsc"
  cp "${dsc%.dsc}.debian.tar.xz" "$pdir/" 2>/dev/null || true
  targets+=("$repo")
done
[ "${#targets[@]}" -gt 0 ] || { echo "no mappable .dsc for $pkg"; exit 1; }

# _multibuild with only the flavours we have sources for
{ echo "<multibuild>"
  for t in "${targets[@]}"; do echo "  <flavor>$t</flavor>"; done
  echo "</multibuild>"; } > "$pdir/_multibuild"

( cd "$pdir"
  osc addremove >/dev/null
  if [ "$DRY" = 1 ]; then osc st; else
    osc ci -m "CI: $pkg $ver $(date -u +%FT%TZ) from ${GITHUB_SHA:-$(git -C "$ROOT" rev-parse --short HEAD)}"
  fi )
echo "obs-sync: $pkg $ver -> $PROJECT  [${targets[*]}]$([ "$DRY" = 1 ] && echo '  (dry-run)')"
