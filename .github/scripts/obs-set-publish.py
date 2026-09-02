#!/usr/bin/env python3
"""obs-set-publish.py <series> <target> enable|disable
   obs-set-publish.py --disable-missing <passed.txt>

Edits the OBS package meta so <repository-for-target> has <publish><enable/> or
<disable/>. Uses `osc meta pkg -e` semantics via a fetch/modify/put cycle.
"""
import subprocess, sys, xml.etree.ElementTree as ET, pathlib

PROJECT = "home:kami911:nvidia-legacy:dkms"
REPO = {
    "debian11": "Debian_11", "debian12": "Debian_12", "debian13": "Debian_13",
    "ubuntu2004": "xUbuntu_20.04", "ubuntu2204": "xUbuntu_22.04", "ubuntu2404": "xUbuntu_24.04",
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


if sys.argv[1] == "--disable-missing":
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
