#!/usr/bin/env bash
# obs-sync.sh — push CI-rendered source packages to OBS.
#
#   obs-sync.sh <series> [--project home:kami911:nvidia-legacy:dkms] [--dry-run]
#
# Expects, in $BUILDDIR (default ../build):
#   nvidia-legacy-<series>_<ver>-*.dsc              one per target
#   nvidia-legacy-<series>_<ver>.orig.tar.xz        + optional -i386
#   nvidia-legacy-<series>_<ver>-*.debian.tar.xz
#
# Writes alternative .dsc names (nvidia-legacy-<series>-<OBS_repo>.dsc) so a
# single OBS package builds all targets via _multibuild.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILDDIR="${BUILDDIR:-$ROOT/../build}"
PROJECT="home:kami911:nvidia-legacy:dkms"
DRY=0
series="${1:?usage: obs-sync.sh <series> [--project P] [--dry-run]}"; shift || true
while [ $# -gt 0 ]; do case "$1" in
  --project) PROJECT="$2"; shift ;; --dry-run) DRY=1 ;; esac; shift; done
command -v osc >/dev/null || { echo "osc not installed"; exit 1; }

pkg="nvidia-legacy-$series"
wd="$(mktemp -d)"; trap 'rm -rf "$wd"' EXIT
( cd "$wd" && osc co "$PROJECT" "$pkg" --current-dir 2>/dev/null || osc mkpac "$pkg" )
pdir="$wd/$pkg"; mkdir -p "$pdir"

declare -A repo_of=(
  [debian11]=Debian_11 [debian12]=Debian_12 [debian13]=Debian_13
  [ubuntu2004]=xUbuntu_20.04 [ubuntu2204]=xUbuntu_22.04 [ubuntu2404]=xUbuntu_24.04)

cp "$BUILDDIR/${pkg}_"*.orig*.tar.* "$pdir/"
for dsc in "$BUILDDIR/${pkg}_"*-*.dsc; do
  base="$(basename "$dsc")"
  # target encoded in the changelog codename -> map to OBS repo
  codename="$(dpkg-scanpackages /dev/null 2>/dev/null; awk '/^Distribution:/{print $2}' "$dsc" 2>/dev/null || true)"
  # simpler: derive from the version suffix ~<codename>1
  suffix="$(sed -n 's/.*~\([a-z]*\)[0-9]*\.dsc/\1/p' <<<"$base")"
  case "$suffix" in
    trixie) repo=Debian_13;; bookworm) repo=Debian_12;; bullseye) repo=Debian_11;;
    noble) repo=xUbuntu_24.04;; jammy) repo=xUbuntu_22.04;; focal) repo=xUbuntu_20.04;;
    *) echo "cannot map $base"; continue;;
  esac
  cp "$dsc" "$pdir/${pkg}-${repo}.dsc"
  cp "${dsc%.dsc}.debian.tar.xz" "$pdir/" 2>/dev/null || true
done
cp "$ROOT/_obs/_multibuild" "$pdir/_multibuild"

( cd "$pdir"
  osc addremove
  if [ "$DRY" = 1 ]; then osc st; else
    osc ci -m "CI: $pkg $(date -u +%FT%TZ) from ${GITHUB_SHA:-$(git -C "$ROOT" rev-parse --short HEAD)}"
  fi )
echo "obs-sync: $pkg -> $PROJECT ${DRY:+(dry-run)}"
