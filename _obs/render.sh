#!/usr/bin/env bash
# render.sh — expand the _obs/*.in templates for a concrete OBS project.
#
#   OBS_PROJECT=home:<login>:nvidia-legacy:dkms _obs/render.sh prj      > (project meta)
#   OBS_PROJECT=... _obs/render.sh pkg <series> <version>              > package-meta.xml
#   OBS_PROJECT=... _obs/render.sh prjconf                             > prjconf
#
# OBS_USER defaults to the segment after "home:" in OBS_PROJECT.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

: "${OBS_PROJECT:?set OBS_PROJECT, e.g. home:KAMI911:nvidia-legacy:dkms}"
case "$OBS_PROJECT" in
  home:*:*) OBS_USER="${OBS_USER:-$(cut -d: -f2 <<<"$OBS_PROJECT")}" ;;
  *)        OBS_USER="${OBS_USER:?OBS_PROJECT is not a home: project — set OBS_USER}" ;;
esac

sub() { sed -e "s|@OBS_PROJECT@|$OBS_PROJECT|g" -e "s|@OBS_USER@|$OBS_USER|g" \
            -e "s|@SERIES@|${1:-}|g" -e "s|@VERSION@|${2:-}|g"; }

case "${1:?prj|pkg|prjconf}" in
  prj)     sub < "$here/project-meta.xml.in" ;;
  pkg)     sub "${2:?series}" "${3:?version}" < "$here/package-meta.xml.in" ;;
  prjconf) cat "$here/prjconf" ;;
  *) echo "unknown: $1" >&2; exit 2 ;;
esac
