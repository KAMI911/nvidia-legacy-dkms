# Security

## The drivers themselves

These are **end-of-life proprietary drivers**. NVIDIA no longer issues security
fixes for any series packaged here.

| Series | Upstream security support | Notes |
|---|---|---|
| 470xx | ended ~2024 | last legacy branch with fixes |
| 390xx | ended 2022-12 | |
| 340xx | ended 2019-12 | **known unpatched CVEs** (e.g. CVE-2019-5665..5671) |
| 304xx | ended 2017-09 | **known unpatched CVEs** |
| 173/96/71xx | 2011–2013 | historical only |

The `340/304/173/96/71` metapackages print a prominent warning via `debconf` on
install. Use them only on isolated / offline machines, or where the hardware
leaves no alternative.

## What this project *does* guarantee

- **Provenance**: every `.run` is pinned by SHA-256 in `common/drivers.yaml`;
  `verify-run.sh` is a hard release gate. No blob is committed to git.
- **Reproducibility**: OBS clean-chroot builds + a `reprotest` bit-identical
  rebuild check. Each release keeps its `.buildinfo`.
- **Patch transparency**: every compatibility patch has a `PROVENANCE.toml`
  entry (origin repo, commit, license, what it fixes). CI fails on an
  undocumented patch.
- **No untested binaries ship**: the OBS `publish` flag is only enabled for a
  `(series, target, arch)` after the full no-GPU gate passes.

## Reporting

Open a private security advisory on the GitHub repo, or email the maintainer
listed in `debian/control`. Packaging/tooling issues are fixed here; driver
vulnerabilities are upstream's and will not be.
