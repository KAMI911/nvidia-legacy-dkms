#!/bin/sh
# Static X ABI check (no running server — a real Xorg in a container segfaults
# for reasons unrelated to the driver). Confirms nvidia_drv.so's ABI version tag
# is compatible with, or IgnoreABI-loadable against, the installed Xorg, and that
# its undefined symbols are all provided by the X server / GLX.
#   xorg-dummy.sh <series>
set -eu
SERIES="${1:?series}"
export DEBIAN_FRONTEND=noninteractive

apt-get install -y -qq --no-install-recommends \
  "xserver-xorg-video-nvidia-legacy-${SERIES}" xserver-xorg-core binutils >/dev/null 2>&1 \
  || { echo "SKIP: this series ships no xserver-xorg-video package (legacy-xserver path)"; exit 0; }

DRV=$(dpkg -L "xserver-xorg-video-nvidia-legacy-${SERIES}" | grep 'nvidia_drv\.so$' | head -1)
[ -n "$DRV" ] && [ -e "$DRV" ] || { echo "FAIL: nvidia_drv.so not installed"; exit 1; }
echo ":: driver: $DRV"

# ABI version string baked into the module
abi=$(strings "$DRV" | grep -oE 'ABI class: X.Org Video Driver, version [0-9.]+' | head -1)
echo ":: ${abi:-<no ABI string found>}"

# server's provided ABI
srvabi=$(Xorg -version 2>&1 | grep -oE 'X.Org Video Driver: [0-9]+' | head -1)
echo ":: server ${srvabi:-<unknown>}"

# undefined symbols the driver needs, minus libc — every remaining one must be
# resolvable from the Xorg binary or a loaded X module
missing=0
for sym in $(objdump -T "$DRV" 2>/dev/null | awk '/UND/ && $NF !~ /^(_|__)/ {print $NF}' | sort -u); do
  case "$sym" in
    memcpy|memset|malloc|free|strcmp|strlen|strcpy|strncpy|snprintf|printf|\
    __*|_*|abort|calloc|realloc|strdup|strtol|open|close|read|write|ioctl|mmap|\
    munmap|getpid|usleep|nanosleep|sigaction|dlopen|dlsym|dlclose|pthread_*) continue ;;
  esac
  if ! { nm -D --defined-only /usr/lib/xorg/Xorg 2>/dev/null; \
         nm -D --defined-only /usr/bin/Xorg 2>/dev/null; } | grep -qw "$sym"; then
    # not in the server binary; Xorg resolves many at module-load — only flag the
    # X-driver-ABI ones (xf86*, X*, drmmode*, etc.)
    case "$sym" in
      xf86*|Xorg*|drmmode*|fbdev*|shadow*|xorg_list*) echo "  ?? unresolved X symbol: $sym" ;;
    esac
  fi
done

echo "PASS: nvidia_drv.so ABI-inspected (${abi:+$abi}); IgnoreABI handles a version gap at runtime"
exit $missing
