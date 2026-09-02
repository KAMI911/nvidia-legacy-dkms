#!/bin/sh
# Runs inside the throwaway distro container (see run.sh). No GPU, no insmod.
# Exit 0 = built + verified; 77 = headers not available (skip); other = fail.
set -eu
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  dkms build-essential kmod "$KPKG" dpkg-dev 2>/dev/null || {
    echo "headers $KPKG not installable"; exit 77; }

apt-get install -y -qq "$DEB" || dpkg -i "$DEB" || { apt-get -f install -y -qq; dpkg -i "$DEB"; }

NAME="nvidia-legacy-${SERIES}"
VER="$(dpkg-query -W -f='${Version}' "${NAME}-kernel-dkms" | sed 's/-[^-]*$//; s/.*://')"
KVER="$KABI"
[ -d "/lib/modules/$KVER/build" ] || KVER="$(ls /lib/modules | head -1)"

echo ":: dkms build $NAME/$VER -k $KVER"
dkms build -m "$NAME" -v "$VER" -k "$KVER" --no-clean-kernel || {
  echo "---- make.log ----"
  cat "/var/lib/dkms/$NAME/$VER/build/make.log" 2>/dev/null | tail -80
  exit 1
}

rc=0
for ko in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  path="/var/lib/dkms/$NAME/$VER/$KVER/*/module/$ko.ko"
  # shellcheck disable=SC2086
  set -- $path
  if [ -f "$1" ]; then
    vm="$(modinfo -F vermagic "$1" 2>/dev/null || true)"
    sv="$(modinfo -F srcversion "$1" 2>/dev/null || true)"
    lic="$(modinfo -F license "$1" 2>/dev/null || true)"
    echo "   $ko.ko  vermagic='$vm'  srcversion='$sv'  license='$lic'"
    case "$vm" in "$KVER"*) : ;; *) echo "   !! vermagic mismatch"; rc=1;; esac
    [ -n "$sv" ] || { echo "   !! empty srcversion"; rc=1; }
  else
    case "$ko" in
      nvidia|nvidia-modeset|nvidia-uvm) echo "   !! $ko.ko missing"; rc=1;;
      *) echo "   ($ko.ko absent — acceptable on this kernel)";;
    esac
  fi
done

# symbol resolution without loading: stage the .ko into /lib/modules and depmod -n
mkdir -p "/lib/modules/$KVER/updates/dkms"
cp /var/lib/dkms/"$NAME"/"$VER"/"$KVER"/*/module/*.ko "/lib/modules/$KVER/updates/dkms/" 2>/dev/null || true
if depmod -n "$KVER" 2>&1 | grep -i "needs unknown symbol"; then
  echo "   !! unresolved symbols"; rc=1
else
  echo "   depmod: all symbols resolved"
fi
exit $rc
