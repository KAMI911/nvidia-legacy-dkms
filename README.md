# nvidia-legacy-dkms

Reproducible **DKMS** packages for the legacy NVIDIA drivers on Debian & Ubuntu.
One source tree per driver series; the kernel module is (re)built on the user's
machine for **every** installed kernel — Debian stock, Ubuntu HWE, the Ubuntu
kernel PPA and mainline PPA included.

The prebuilt-`.ko` sibling is [`nvidia-legacy-modules`](https://github.com/kami911/nvidia-legacy-modules).
Shared tooling, templates and patches live in
[`nvidia-legacy-common`](https://github.com/kami911/nvidia-legacy-common) (the `common/` submodule).

## Series & targets

See [`series.yaml`](series.yaml). Current build set:

| Series | Version | Status | amd64 | i386 (kmod) | Notes |
|---|---|---|---|---|---|
| 470xx | 470.256.02 | supported | ✅ | — | Kepler; amd64 only upstream |
| 390xx | 390.157 | supported | ✅ | ✅ | Fermi/Kepler |
| 340xx | 340.108 | supported | ✅ | ✅ | GeForce 8–300; **known security issues** |
| 304xx | 304.137 | best-effort | ✅ | ✅ | GeForce 6/7; Xorg ABI ≤ 23 |
| 173xx / 96xx / 71xx | — | experimental | ⚠️ | ⚠️ | old X ABI only (Debian 11 / older) |

Targets: Debian 11/12/13, Ubuntu 20.04/22.04/24.04 — each amd64, plus i386
kernel modules where the distro still ships an i386 kernel (Debian only), plus
i386 runtime libraries everywhere via multiarch.

## Layout

```
common/                  submodule -> nvidia-legacy-common
series.yaml               which (series × target) combos this repo builds
scripts/regen.sh          render packaging/ from common/ (run after a submodule bump)
packaging/<series>/<target>/debian/   generated, committed
_obs/                     Open Build Service project meta + source services
.github/workflows/        static · build-reprotest · dkms-matrix · autopkgtest · qemu · release
tests/                    the no-GPU test harness (see tests/README.md)
```

## Build locally

```sh
git submodule update --init
make regen                       # render every packaging/<series>/<target>
make source SERIES=390xx TARGET=debian13     # -> ../build/*.dsc + orig tarballs
make build  SERIES=390xx TARGET=debian13     # sbuild amd64 + i386
make test   SERIES=390xx TARGET=debian13     # static + dkms-matrix + autopkgtest + qemu
```

## Release gate

A `(series, target, arch)` build is publishable **only** when, in CI:
`static` ✅ · `build-reprotest` ✅ (bit-identical rebuild) · `dkms-matrix` ✅
(builds against every kernel in `tests/dkms-matrix/kernels.yaml`) ·
`autopkgtest` ✅ · `qemu` ✅.
`best-effort` / `experimental` series report results but do not block.
`release.yml` flips the OBS `publish` flag; nothing ships otherwise.

## Security

Legacy drivers receive no upstream security fixes. See [SECURITY.md](SECURITY.md).
The 340/304/173/96/71 series have publicly known, unpatched vulnerabilities and
print a warning on install.
