# OBS integration — nvidia-legacy-dkms

Authoritative multi-distro / multi-arch builds run on the **Open Build Service**.
Project: `home:kami911:nvidia-legacy:dkms` (mirror to a private OBS if preferred).

## Model: CI renders, OBS builds

We do **not** let OBS render the `debian/` tree or fetch the `.run` blobs. CI
(`.github/workflows/release.yml`) is the single deterministic source:

1. `regen.sh` renders `packaging/<series>/<target>/debian/`.
2. `common/scripts/verify-run.sh` checks the pinned sha256 of every `.run`.
3. `common/scripts/assemble-source.sh` builds the `.orig.tar.xz` (+ `-i386`).
4. `dpkg-source -b` → `.dsc`.
5. `tools/obs-sync.sh` (`osc`) commits `.dsc` + tarballs into the matching OBS
   package, one OBS package per `(series)`, per-distro via alternative `.dsc`
   (`nvidia-legacy-<series>-<OBS_repo>.dsc`) — see `_multibuild`.
6. OBS builds in a clean chroot for every repository × arch.
7. `release.yml` sets `<publish><enable/>` on the package **only** after the
   no-GPU test gate is green for that repo/arch; until then `<publish><disable/>`.

This keeps reproducibility anchored in Git + pinned hashes, and uses OBS purely
as the clean-room builder / apt-repo host.

## Files

| File | Purpose |
|---|---|
| `project-meta.xml` | `osc meta prj home:kami911:nvidia-legacy:dkms -F project-meta.xml` |
| `prjconf` | `osc meta prjconf ... -F prjconf` — determinism knobs, macros |
| `_multibuild` | per-distro `.dsc` flavours for a single OBS package |
| `_service` | fallback: let OBS pull from Git (disabled by default) |
| `package-meta.xml.in` | template per-series OBS package meta (publish flag toggled by CI) |

## Repositories (build targets)

`Debian_11 Debian_12 Debian_13 xUbuntu_20.04 xUbuntu_22.04 xUbuntu_24.04`,
each `x86_64`; `Debian_*` additionally `i586` for the i386 kernel modules.
