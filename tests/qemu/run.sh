#!/usr/bin/env bash
# qemu/run.sh <series> <target>
#
# Boot a minimal cloud image of <target> in QEMU with NO GPU device, install the
# built packages from a local file apt repo, then:
#   * modprobe nvidia            -> must insert (device-less load) OR give the
#                                   documented ENODEV; must NOT taint/oops
#   * dmesg                      -> must contain "NVRM: loading" / "nvidia: loaded"
#   * nvidia-smi                 -> exit 9 (no device) is OK; segfault is NOT
#   * Xorg -config dummy         -> loads nvidia_drv.so + GLX, ABI-clean
#
# Uses cloud-init for provisioning. Falls back to skippable if KVM absent.
set -euo pipefail
. "$(dirname "$0")/../lib.sh"
series="${1:?series}"; target="${2:?target}"
qdir="$(dirname "$0")"

[ -e /dev/kvm ] || { skip "no /dev/kvm — qemu stage skipped"; summary; exit 0; }
command -v qemu-system-x86_64 >/dev/null || { skip "qemu not installed"; summary; exit 0; }

declare -A cloud=(
  [debian11]="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
  [debian12]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  [debian13]="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  [ubuntu2004]="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
  [ubuntu2204]="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  [ubuntu2404]="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img")
url="${cloud[$target]:?unknown target}"

cache="${NVL_CACHE_DIR:-$HOME/.cache/nvidia-legacy}/qemu"; mkdir -p "$cache"
base="$cache/$(basename "$url")"
[ -s "$base" ] || { info "fetch $url"; curl -fSL -o "$base" "$url"; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
qemu-img create -f qcow2 -b "$base" -F qcow2 "$work/disk.qcow2" 12G >/dev/null

# local apt repo from build artifacts
mkdir -p "$work/repo"
cp "$BUILDDIR"/nvidia-legacy-"$series"*.deb "$work/repo/" 2>/dev/null || { no "no debs"; summary; exit 1; }
( cd "$work/repo" && dpkg-scanpackages -m . | gzip -9 > Packages.gz )

# cloud-init: mount the repo (virtio-9p), run the in-guest script
cat > "$work/user-data" <<EOF
#cloud-config
package_update: false
runcmd:
  - [ mkdir, -p, /mnt/repo ]
  - [ mount, -t, 9p, -o, "trans=virtio,version=9p2000.L", repo, /mnt/repo ]
  - [ mount, -t, 9p, -o, "trans=virtio,version=9p2000.L", t, /mnt/t ]
  - "echo 'deb [trusted=yes] file:/mnt/repo ./' > /etc/apt/sources.list.d/nvl.list"
  - [ bash, /mnt/t/_in-guest.sh, "$series" ]
  - [ poweroff ]
EOF
touch "$work/meta-data"
( cd "$work" && cloud-localds seed.iso user-data meta-data )

info "boot qemu ($target, no GPU)…"
set +e
timeout 900 qemu-system-x86_64 \
  -enable-kvm -m 2048 -smp 2 -nographic \
  -drive file="$work/disk.qcow2",if=virtio \
  -drive file="$work/seed.iso",if=virtio,format=raw \
  -virtfs local,path="$work/repo",mount_tag=repo,security_model=none \
  -virtfs local,path="$qdir",mount_tag=t,security_model=none \
  -serial mon:stdio | tee "$work/console.log"
set -e

echo "==== guest verdict ===="
grep -E '^\[nvl-qemu\]' "$work/console.log" || true
if grep -q '^\[nvl-qemu\] RESULT: PASS' "$work/console.log"; then
  ok "qemu module-load + Xorg ABI ($target)"
elif grep -q '^\[nvl-qemu\] RESULT: SKIP' "$work/console.log"; then
  skip "qemu ($target): guest skipped"
else
  no "qemu ($target): see $work/console.log"
fi
summary
