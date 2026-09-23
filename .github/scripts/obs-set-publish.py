#!/usr/bin/env python3
"""obs-set-publish.py <series> <target> enable|disable
   obs-set-publish.py --disable-missing <passed.txt>
   obs-set-publish.py --gate <series> <target> [timeout_seconds] [--dry-run]

Edits the OBS package meta so <repository-for-target> has <publish><enable/> or
<disable/>. Uses `osc meta pkg -e` semantics via a fetch/modify/put cycle.

--gate waits for the real OBS build of that (series,target) to finish (not the
CI/sbuild proxy of it — the two environments can disagree, e.g. a lagging OBS
distro mirror pinning a different kernel ABI than CI saw) and only enables
publish if OBS itself reports every arch of that repository as "succeeded".
Any other outcome (a real failure, or the wait timing out) disables publish
and exits non-zero, so callers can warn-and-continue per combo. --dry-run
still waits for and reads the real result but only prints what it would set.
"""
import os, subprocess, sys, xml.etree.ElementTree as ET, pathlib

PROJECT = os.environ.get("OBS_PROJECT", "home:KAMI911:nvidia-legacy:dkms")
REPO = {
    "debian11": "Debian_11", "debian12": "Debian_12", "debian13": "Debian_13",
    "ubuntu2004": "xUbuntu_20.04", "ubuntu2204": "xUbuntu_22.04", "ubuntu2404": "xUbuntu_24.04", "ubuntu2604": "xUbuntu_26.04",
}


def osc(*a, inp=None):
    return subprocess.run(["osc", *a], input=inp, text=True,
                          capture_output=True, check=True).stdout


def set_flag(series: str, target: str, enable: bool):
    pkg = f"nvidia-legacy-{series}"
    meta = osc("meta", "pkg", PROJECT, pkg)
    root = ET.fromstring(meta)
    pub = root.find("publish")
    if pub is None:
        pub = ET.SubElement(root, "publish")
    repo = REPO[target]
    for e in list(pub):
        if e.get("repository") == repo:
            pub.remove(e)
    ET.SubElement(pub, "enable" if enable else "disable", {"repository": repo})
    out = ET.tostring(root, encoding="unicode")
    osc("meta", "pkg", PROJECT, pkg, "-F", "-", inp=out)
    print(f"{pkg}: {repo} -> {'enable' if enable else 'disable'}")


def wait_and_gate(series: str, target: str, timeout: int, dry: bool = False):
    pkg = f"nvidia-legacy-{series}"
    repo = REPO[target]
    flavor_pkg = f"{pkg}:{repo}"

    # NOTE: no -M/--multibuild-package — the installed osc's CLI passes it
    # through as multibuild_packages=, which show_results_meta() in this
    # version doesn't accept (TypeError). -r plus our own package== filter
    # below narrows to the same rows without it.
    proc = subprocess.run(
        ["timeout", str(timeout), "osc", "results", PROJECT, pkg,
         "-r", repo, "--xml", "-w"],
        text=True, capture_output=True,
    )
    if proc.returncode == 124:
        print(f"{pkg}/{repo}: timed out after {timeout}s waiting for OBS build", file=sys.stderr)
        if dry:
            print(f"(dry-run) would set {pkg}: {repo} -> disable")
        else:
            set_flag(series, target, False)
        sys.exit(1)
    if proc.returncode != 0:
        print(f"{pkg}/{repo}: osc results failed: {proc.stderr}", file=sys.stderr)
        sys.exit(1)

    root = ET.fromstring(proc.stdout)
    codes = []
    for result in root.iter("result"):
        if result.get("repository") != repo:
            continue
        for status in result.findall("status"):
            if status.get("package") == flavor_pkg:
                codes.append((result.get("arch"), status.get("code")))

    if not codes:
        print(f"{pkg}/{repo}: no build results found for flavor {repo}", file=sys.stderr)
        sys.exit(1)

    ok = all(code == "succeeded" for _, code in codes)
    print(f"{pkg}/{repo}: {codes} -> {'PASS' if ok else 'FAIL'}")
    if dry:
        print(f"(dry-run) would set {pkg}: {repo} -> {'enable' if ok else 'disable'}")
    else:
        set_flag(series, target, ok)
    if not ok:
        sys.exit(1)


if sys.argv[1] == "--gate":
    _rest = [a for a in sys.argv[2:] if a != "--dry-run"]
    _dry = "--dry-run" in sys.argv[2:]
    _timeout = int(_rest[2]) if len(_rest) > 2 else 900
    wait_and_gate(_rest[0], _rest[1], _timeout, _dry)
elif sys.argv[1] == "--disable-missing":
    passed = {tuple(l.split()) for l in pathlib.Path(sys.argv[2]).read_text().split("\n") if l and not l.startswith("#")}
    # every known combo not in passed -> disable
    import yaml
    doc = yaml.safe_load(open(pathlib.Path(__file__).parents[2] / "series.yaml"))
    for s, cfg in doc["build"].items():
        for t in cfg["targets"]:
            if (s, t) not in passed:
                try:
                    set_flag(s, t, False)
                except subprocess.CalledProcessError as e:
                    print(f"warn: {s}/{t}: {e.stderr}", file=sys.stderr)
else:
    set_flag(sys.argv[1], sys.argv[2], sys.argv[3] == "enable")
