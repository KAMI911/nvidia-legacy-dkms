#!/bin/sh
# Runs inside the throwaway distro container (see run.sh). No GPU, no insmod.
# Exit 0 = built + verified; 77 = headers not available (skip); other = fail.
set -eu
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  dkms build-essential kmod "$KPKG" dpkg-dev 2>/dev/null || {
    echo "headers $KPKG not installable"; exit 77; }

# Installing the dkms .deb runs its postinst, which tries to build for EVERY
# installed kernel. That may fail here (e.g. an RT kernel we don't support yet)
# — don't let it abort the script; the explicit `dkms build -k $KVER` below is
# the authority for THIS kernel and dumps make.log on failure.
apt-get install -y -qq "$DEB" || dpkg -i "$DEB" || apt-get -f install -y -qq || true
dpkg -i "$DEB" >/dev/null 2>&1 || true
dpkg-query -W -f='${Status}\n' "nvidia-legacy-${SERIES}-kernel-dkms" 2>/dev/null | grep -qE 'unpacked|installed' \
  || { echo "kernel-dkms .deb did not unpack"; exit 1; }

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
# dkms may leave the built modules in /var/lib/dkms/.../module/ OR install them
# (possibly .ko.xz / .ko.zst compressed) into /lib/modules/$KVER/updates/dkms/
find_ko() {  # find_ko <name> -> prints the path or nothing
  local n="$1" p
  for p in "/var/lib/dkms/$NAME/$VER/$KVER"/*/module/"$n".ko \
           "/lib/modules/$KVER/updates/dkms/$n".ko \
           "/lib/modules/$KVER/updates/dkms/$n".ko.* ; do
    [ -e "$p" ] && { echo "$p"; return; }
  done
}
for ko in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  f="$(find_ko "$ko")"
  if [ -n "$f" ]; then
    case "$f" in
      *.ko) vm="$(modinfo -F vermagic "$f" 2>/dev/null)"; sv="$(modinfo -F srcversion "$f" 2>/dev/null)"
            echo "   $ko: $(basename "$f")  vermagic='$vm'  srcversion='$sv'"
            case "$vm" in "$KVER"*) : ;; ""*) : ;; *) echo "   !! vermagic mismatch"; rc=1;; esac ;;
      *)    echo "   $ko: $(basename "$f")  (compressed, installed)" ;;
    esac
  else
    case "$ko" in
      nvidia|nvidia-modeset|nvidia-uvm) echo "   !! $ko.ko not found"; rc=1;;
      *) echo "   ($ko.ko absent — acceptable on this kernel)";;
    esac
  fi
done

if depmod "$KVER" 2>&1 | grep -i "needs unknown symbol"; then
  echo "   !! unresolved symbols"; rc=1
else
  echo "   depmod: OK"
fi
exit $rc
