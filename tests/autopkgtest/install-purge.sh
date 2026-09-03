#!/bin/sh
# install / reinstall / upgrade / purge the driver metapackage and assert the
# system is left clean. Runs in a container with NO GPU.
#   install-purge.sh <series>   (also usable as an in-archive autopkgtest)
set -eu
SERIES="${1:?series}"
PKG="nvidia-legacy-${SERIES}-driver"
export DEBIAN_FRONTEND=noninteractive

before="$(mktemp)"; after="$(mktemp)"
dpkg -l | awk '{print $2}' | sort > "$before"

echo ":: install $PKG"
apt-get install -y "$PKG"

echo ":: verify pieces landed"
dpkg -s "nvidia-legacy-${SERIES}-driver-libs" >/dev/null
dpkg -s "nvidia-legacy-${SERIES}-kernel-support" >/dev/null
test -e /lib/modprobe.d/nvidia-blacklists-nouveau.conf
test -e "/usr/share/nvidia-legacy-${SERIES}/xorg.conf.d/20-nvidia-legacy-${SERIES}.conf"

echo ":: reinstall (idempotent maintainer scripts)"
apt-get install --reinstall -y "$PKG"

echo ":: purge"
export SUDO_FORCE_REMOVE=yes
# only genuinely-installed real packages — dpkg-query -W also prints virtual
# names (e.g. the kernel-dkms package Provides nvidia-legacy-<s>-kernel-module),
# and feeding those to apt-get purge aborts with "Unable to locate package".
mapfile -t ours < <(dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\n' \
  'nvidia-legacy-*' 'xserver-xorg-video-nvidia-legacy-*' 2>/dev/null \
  | awk -F'\t' '$1 ~ /^.i/ {print $2}' | sort -u)
[ "${#ours[@]}" -gt 0 ] && apt-get purge -y "${ours[@]}"
# autoremove only what WE pulled in, never touch base packages
apt-get autoremove --purge -y -o APT::Get::AutomaticRemove::SuggestsImportant=false || true

echo ":: NVIDIA packages still installed after purge (must be none):"
residue=$(dpkg-query -W -f='${db:Status-Abbrev}\t${Package}\n' \
  'nvidia-legacy-*' 'xserver-xorg-video-nvidia-legacy-*' 2>/dev/null \
  | awk -F'\t' '$1 ~ /^.i/ || $1 ~ /^.c/ {print $2}')
if [ -n "$residue" ]; then
  echo "$residue"
  echo "FAIL: nvidia package residue"; exit 1
fi
test ! -e /lib/modprobe.d/nvidia-blacklists-nouveau.conf || { echo "FAIL: blacklist left behind"; exit 1; }
test ! -e /etc/X11/xorg.conf.d/20-nvidia-legacy-${SERIES}.conf || { echo "FAIL: xorg snippet left behind"; exit 1; }
echo "PASS: clean install/purge"
