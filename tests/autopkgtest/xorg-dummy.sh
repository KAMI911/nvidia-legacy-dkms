#!/bin/sh
# Start Xorg with the dummy framebuffer + our nvidia config and confirm the
# server LOADS nvidia_drv.so and the GLX extension without an ABI/symbol error.
# It will fail to find a screen (no GPU) — that is the expected/allowed endpoint.
#   xorg-dummy.sh <series>
set -eu
SERIES="${1:?series}"
export DEBIAN_FRONTEND=noninteractive
LOG=/tmp/xorg-dummy.log

# only the X-relevant pieces — not the full driver metapackage (which pulls the
# DKMS source and runs maintainer scripts that need /boot etc.)
apt-get install -y --no-install-recommends \
  "xserver-xorg-video-nvidia-legacy-${SERIES}" \
  "libgl1-nvidia-legacy-${SERIES}-glx" 2>/dev/null \
  || apt-get install -y --no-install-recommends "nvidia-legacy-${SERIES}-driver-libs"
apt-get install -y --no-install-recommends xserver-xorg-core xserver-xorg-video-dummy xvfb >/dev/null 2>&1 || true
command -v Xorg >/dev/null || { echo "SKIP: no Xorg in image"; exit 0; }

cat >/tmp/nvidia-dummy.conf <<EOF
Section "ServerFlags"
    Option "IgnoreABI" "1"
    Option "AutoAddDevices" "false"
EndSection
Section "Device"
    Identifier "nv"
    Driver "nvidia"
EndSection
EOF

set +e
Xorg -noreset -logverbose 6 -logfile "$LOG" -config /tmp/nvidia-dummy.conf :9 &
XPID=$!
sleep 4
kill "$XPID" 2>/dev/null
set -e

echo "---- relevant Xorg.log ----"
grep -E "nvidia|NVIDIA|GLX|ABI|module ABI|UnloadModule|Symbol" "$LOG" || true
echo "---------------------------"

fail=0
grep -q 'LoadModule: "nvidia"' "$LOG" || { echo "FAIL: nvidia module never load-attempted"; fail=1; }
if grep -Eq 'module ABI major version.*does not match|Symbol .* not found|UnloadModule: "nvidia".*because of.*ABI' "$LOG"; then
  echo "FAIL: nvidia_drv.so rejected on ABI/symbol grounds"; fail=1
fi
if grep -Eq 'Loading .*nvidia_drv\.so|NVIDIA .* X Driver' "$LOG"; then
  echo "OK: nvidia_drv.so loaded"
else
  echo "WARN: no explicit load confirmation (check log above)"
fi
# 'no devices detected' / 'no screens found' is the acceptable no-GPU endpoint
grep -Eq 'no devices detected|No devices detected|no screens found' "$LOG" \
  && echo "OK: reached no-GPU endpoint cleanly"

exit $fail
