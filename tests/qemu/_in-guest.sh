#!/bin/bash
# Runs inside the QEMU guest (no GPU). Prints [nvl-qemu] lines the host greps.
set -uo pipefail
SERIES="${1:?}"
say() { echo "[nvl-qemu] $*"; }
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
if ! apt-get install -y -qq "linux-headers-$(uname -r)"; then
  say "RESULT: SKIP (no matching headers in guest)"; exit 0
fi
if ! apt-get install -y -qq "nvidia-legacy-${SERIES}-driver"; then
  say "RESULT: FAIL (package install failed)"; exit 1
fi

NAME="nvidia-legacy-${SERIES}"
VER="$(dpkg-query -W -f='${Version}' "${NAME}-kernel-dkms" | sed 's/-[^-]*$//;s/.*://')"
dkms autoinstall -k "$(uname -r)" || true
if ! dkms status | grep -q "installed"; then
  say "RESULT: FAIL (dkms did not install a module)"; exit 1
fi
depmod -a

say "modprobe nvidia (device-less)…"
modprobe nvidia 2>/tmp/mp.err
rc=$?
dmesg | grep -iE 'NVRM|nvidia' | tail -20 | sed 's/^/[nvl-qemu] dmesg: /'
if dmesg | grep -qiE 'BUG:|Oops|general protection fault|kernel NULL pointer'; then
  say "RESULT: FAIL (kernel oops on load)"; exit 1
fi
if [ $rc -ne 0 ] && ! grep -qiE 'No such device|ENODEV' /tmp/mp.err; then
  say "modprobe rc=$rc err=$(cat /tmp/mp.err)"
  say "RESULT: FAIL (module refused to load for a non-ENODEV reason)"; exit 1
fi
lsmod | grep -q '^nvidia' && say "nvidia module inserted" || say "nvidia not resident (ENODEV path — acceptable)"

say "nvidia-smi…"
nvidia-smi; smi=$?
say "nvidia-smi exit=$smi (9 = no device, acceptable)"
[ $smi -eq 139 ] && { say "RESULT: FAIL (nvidia-smi segfault)"; exit 1; }

say "Xorg ABI check…"
apt-get install -y -qq xserver-xorg-core xserver-xorg-video-dummy >/dev/null
printf 'Section "ServerFlags"\n Option "IgnoreABI" "1"\n Option "AutoAddDevices" "false"\nEndSection\nSection "Device"\n Identifier "nv"\n Driver "nvidia"\nEndSection\n' >/tmp/x.conf
Xorg -noreset -logverbose 6 -logfile /tmp/x.log -config /tmp/x.conf :9 & xp=$!
sleep 4; kill $xp 2>/dev/null
grep -E 'nvidia|GLX|ABI' /tmp/x.log | tail -20 | sed 's/^/[nvl-qemu] xorg: /'
if grep -Eq 'module ABI major version.*does not match|Symbol .* not found' /tmp/x.log; then
  say "RESULT: FAIL (Xorg ABI/symbol rejection)"; exit 1
fi
if ! grep -q 'LoadModule: "nvidia"' /tmp/x.log; then
  say "RESULT: FAIL (Xorg never tried nvidia)"; exit 1
fi

say "RESULT: PASS"
exit 0
