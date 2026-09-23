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
7. `obs-push` then waits on the **real** `osc results` for each repository
   (`obs-set-publish.py --gate <series> <target>`, `-w` under a bounded
   timeout) and only flips `<publish><enable/>` if every arch in that
   repository came back `succeeded`. This checks OBS itself, not the CI/sbuild
   proxy of it — the two can disagree (e.g. a lagging OBS distro mirror
   pinning a different kernel ABI than CI saw). A miss just leaves that
   repo `<publish><disable/></publish>` and logs a `::warning::`; it does not
   fail the run. Pass `publish_gate: false` on a manual dispatch to push
   sources without waiting/gating, or run
   `obs-set-publish.py <series> <target> enable` manually.

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
| **obs-push** (`workflow_dispatch`) | applies project meta + prjconf, renders + pushes the selected series' packages, then waits on the real OBS build and enables publish per repo that comes back green. `project_config: false` to skip the meta step; `series: 390xx` to push just one; `publish_gate: false` to push without waiting/gating. |
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
