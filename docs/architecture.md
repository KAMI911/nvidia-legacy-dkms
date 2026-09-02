# Architecture

```
                        ┌──────────────────────────┐
                        │  nvidia-legacy-common     │  (git submodule `common/`)
                        │  drivers.yaml  (truth)    │
                        │  debian-template/<series> │
                        │  patches/<series> + PROV. │
                        │  scripts/                 │
                        └────────────┬─────────────┘
                                     │  render-debian.py + verify-run.sh
                                     ▼
   this repo:  series.yaml ──► scripts/regen.sh ──► packaging/<series>/<target>/debian/
                                     │
                                     ▼
     ┌────────────────────── GitHub Actions (no GPU) ──────────────────────┐
     │ static → build+reprotest → dkms-matrix → autopkgtest → qemu         │
     │  each stage writes <stage>-verdicts.json                            │
     └───────────────────────────────┬───────────────────────────────────┘
                                     │ release-gate.py  (intersect verdicts)
                                     ▼
                     tools/obs-sync.sh  (osc: push .dsc + tarballs)
                                     ▼
              OBS  home:kami911:nvidia-legacy:dkms   (clean-chroot build)
              publish flag per repo/arch ← obs-set-publish.py
                                     ▼
                   apt repo:  deb .../nvidia-legacy:/dkms/<Distro>/ ./
```

## Why the split

- **common** changes rarely and is shared byte-for-byte with `nvidia-legacy-modules`.
- **dkms** vs **modules** are different products (source-on-device vs prebuilt
  per-ABI) with different CI shapes, so they are different repos as requested.
- **CI renders, OBS builds**: keeps the deterministic inputs (templates, pinned
  hashes, patch commit) in git; OBS is only the clean-room + apt host. A build
  can be reproduced from a tag + `common` commit + the pinned `.run` hashes
  without OBS at all (`make build`).

## Determinism anchors

| Input | Pinned by |
|---|---|
| driver blob | `common/drivers.yaml` sha256 (+ `verify-run.sh` gate) |
| packaging | `common` git commit (submodule SHA) |
| patch set | same commit; gate logic in `render-debian.py` + `apply-patches.sh` |
| toolchain | distro point-release / `-updates` snapshot, recorded in `.buildinfo` |
| timestamps | `SOURCE_DATE_EPOCH` = changelog date |
| kernel headers (modules repo) | exact version in `kernels.yaml` / generator output |
