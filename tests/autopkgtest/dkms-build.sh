#!/bin/sh
# In-archive autopkgtest: build the DKMS module against the container's own
# running-kernel headers (isolation-machine gives a real kernel). No insmod.
#   dkms-build.sh <series>
set -eu
SERIES="${1:?series}"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y "linux-headers-$(uname -r)" 2>/dev/null \
  || apt-get install -y linux-headers-generic linux-headers-amd64 \
  || { echo "SKIP: no headers"; exit 77; }
apt-get install -y "nvidia-legacy-${SERIES}-kernel-dkms"

NAME="nvidia-legacy-${SERIES}"
VER="$(dpkg-query -W -f='${Version}' "${NAME}-kernel-dkms" | sed 's/-[^-]*$//;s/.*://')"
dkms status | grep -q "$NAME" || dkms add -m "$NAME" -v "$VER"
dkms build -m "$NAME" -v "$VER" -k "$(uname -r)" \
  || { tail -60 /var/lib/dkms/"$NAME"/"$VER"/build/make.log; exit 1; }
echo "PASS: DKMS build for $(uname -r)"
