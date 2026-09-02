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
apt-get purge -y "$PKG" "nvidia-legacy-${SERIES}-*" || apt-get purge -y "$(dpkg -l 'nvidia-legacy-*' | awk '/^ii/{print $2}')"
apt-get autoremove --purge -y

dpkg -l | awk '{print $2}' | sort > "$after"
echo ":: packages remaining that were not there before:"
if comm -13 "$before" "$after" | grep -q .; then
  comm -13 "$before" "$after"; echo "FAIL: residue"; exit 1
fi
test ! -e /lib/modprobe.d/nvidia-blacklists-nouveau.conf || { echo "FAIL: blacklist left behind"; exit 1; }
test ! -e /etc/X11/xorg.conf.d/20-nvidia-legacy-${SERIES}.conf || { echo "FAIL: xorg snippet left behind"; exit 1; }
echo "PASS: clean install/purge"
