# OBS integration — nvidia-legacy-dkms

Authoritative multi-distro / multi-arch builds run on the **Open Build Service**.
Project: `home:<your-obs-login>:nvidia-legacy:dkms` (or a private OBS).

Everything here is templated on **`OBS_PROJECT`**. `OBS_USER` defaults to the
segment after `home:`. Nothing hardcodes a login.

## Model: CI renders, OBS builds

OBS never renders the `debian/` tree or fetches the `.run` blobs. CI is the
single deterministic source:

1. `regen.sh` renders `packaging/<series>/<target>/debian/`.
2. `common/scripts/verify-run.sh` checks the pinned sha256 of every `.run`.
3. `common/scripts/assemble-source.sh` builds the `.orig.tar.xz` (+ `-i386`).
4. `dpkg-source -b` → `.dsc`.
5. `tools/obs-sync.sh <series>` (`osc`) creates the OBS package if needed
   (**build on, publish off**) and commits `.dsc` + tarballs, one OBS package
   per series, per-distro via alternative `.dsc` (`nvidia-legacy-<series>-<repo>.dsc`)
   and a generated `_multibuild` listing only the targets that have sources.
6. OBS builds in a clean chroot for every repository × arch.
7. Publishing a repository is a **deliberate** step once `osc results` for it is
   green — `.github/scripts/obs-set-publish.py <series> <target> enable`, or a
   manual `osc meta pkg`. Until then the package (and the whole project) is
   `<publish><disable/>`.

## Files

| File | Purpose |
|---|---|
| `project-meta.xml.in` | `@OBS_PROJECT@` / `@OBS_USER@` → `render.sh prj` |
| `package-meta.xml.in` | per-series package meta (`render.sh pkg <series> <ver>`) |
| `prjconf` | `osc meta prjconf <project> -F prjconf` — determinism knobs (no tokens) |
| `_service` | fallback: let OBS pull from Git (disabled by default) |
| `render.sh` | expand the `.in` templates for a concrete `OBS_PROJECT` |

## Bootstrap

Once the `OSC_*` secrets/vars are set (see `../BOOTSTRAP.md` §2), everything is
a GitHub Action — no local `osc` needed:

| Action | Does |
|---|---|
| **obs-push** (`workflow_dispatch`) | applies project meta + prjconf, then renders + pushes the selected series' packages. `project_config: false` to skip the meta step; `series: 390xx` to push just one. |
| **release** (tag `v*`) | full gate (static+smoke+reprotest) → `obs-push` |

Local fallback (needs `osc login`):

```sh
export OBS_PROJECT=home:$(osc whois | cut -d: -f1):nvidia-legacy:dkms
osc meta prj      "$OBS_PROJECT" -F <(_obs/render.sh prj)
osc meta prjconf  "$OBS_PROJECT" -F _obs/prjconf
```

## Repositories (build targets)

`Debian_11 Debian_12 Debian_13` each `x86_64` + `i586` (i386 kernel modules);
`xUbuntu_20.04 xUbuntu_22.04 xUbuntu_24.04` each `x86_64`.

> **Ubuntu note:** `build.opensuse.org` does not always carry a ready
> `Ubuntu:24.04` base project. If the Ubuntu repos stay "unresolvable", drop
> them from `project-meta.xml.in` (Debian covers the reproducible-build goal) or
> point them at a base project that exists on your OBS instance.
