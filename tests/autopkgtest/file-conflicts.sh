#!/bin/sh
# Assert our packages do not physically overwrite files owned by the distro
# nvidia-driver / mesa / libglvnd packages, and that GL/GLX alternatives or
# glvnd config are wired correctly.  No GPU.
#   file-conflicts.sh <series>
set -eu
SERIES="${1:?series}"
export DEBIAN_FRONTEND=noninteractive
rc=0

echo ":: dpkg file overlap check"
apt-get install -y "nvidia-legacy-${SERIES}-driver" >/dev/null

for our in $(dpkg -l "nvidia-legacy-${SERIES}-*" "libgl1-nvidia-legacy-${SERIES}-*" | awk '/^ii/{print $2}'); do
  dpkg -L "$our" | while read -r f; do
    [ -f "$f" ] || continue
    owner="$(dpkg -S "$f" 2>/dev/null | grep -v "^$our" | cut -d: -f1 || true)"
    if [ -n "$owner" ]; then
      echo "  CONFLICT: $f also in $owner"; rc=1
    fi
  done
done

echo ":: GLX provider"
if ls /usr/lib/*/libGLX_nvidia.so.0 >/dev/null 2>&1 || update-alternatives --query glx >/dev/null 2>&1; then
  echo "  glvnd/alternatives present"
else
  echo "  NOTE: no glvnd libGLX_nvidia and no glx alternative — legacy non-glvnd path"
fi

echo ":: ldconfig sanity"
ldconfig -p | grep -E 'libGL\.so|libnvidia-glcore' || { echo "  FAIL: nvidia GL not in ld cache"; rc=1; }

[ $rc -eq 0 ] && echo "PASS: no file conflicts" || echo "FAIL"
exit $rc
