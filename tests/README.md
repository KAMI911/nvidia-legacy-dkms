# No-GPU test harness

Every stage here runs **without an NVIDIA GPU**. A physical card would only add
the final `glxinfo`/`nvidia-smi` smoke check (see `tests/gpu/`, optional,
self-hosted, non-blocking).

| Stage | Script | What it proves | Gate |
|---|---|---|---|
| static | `.github/scripts/static-checks.sh` | lintian clean, hardening (blhc), patch provenance complete, shellcheck, no vendored blob in git | **blocking** |
| build + reprotest | `.github/scripts/sbuild-wrap.sh` + `reprotest` | package builds in a clean chroot for each distro×arch, and a second build is **bit-identical** | **blocking** |
| dkms-matrix | `dkms-matrix/run.sh` | module source compiles against **every** kernel in `kernels.yaml` (distro stock, all HWE points, latest mainline & Ubuntu kernel-PPA); `modinfo` sane; `depmod -n` resolves every symbol | **blocking** |
| autopkgtest | `autopkgtest/*.sh` | clean install/upgrade/purge; no file conflict with `nvidia-driver`/mesa; alternatives + glvnd wired; nouveau blacklist + initramfs hook run | **blocking** |
| qemu | `qemu/run.sh` | in a real VM of the exact distro/kernel with **no GPU**: `modprobe nvidia` inserts (or documented `ENODEV`); `dmesg` shows `NVRM: loading`; dummy Xorg with `IgnoreABI` loads `nvidia_drv.so` + GLX to "no devices" — catches Xorg ABI breakage | **blocking** |
| gpu (optional) | `gpu/smoke.sh` | real `nvidia-smi -q`, `glxinfo -B`, `__GL_SYNC_TO_VBLANK` glxgears frames | non-blocking, self-hosted only |

`best-effort` / `experimental` series (see `series.yaml`) run all stages but
their failures are reported, not gated.

## Run one combo locally

```sh
tests/run-all.sh 390xx debian13
```

Needs: `sbuild`, `reprotest`, `diffoscope`, `autopkgtest`, `qemu-system-x86_64`,
`mmdebstrap`. `tests/run-all.sh --deps` installs them on a Debian/Ubuntu host.
