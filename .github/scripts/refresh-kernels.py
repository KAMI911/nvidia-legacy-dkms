#!/usr/bin/env python3
"""refresh-kernels.py — append newly released kernels to tests/dkms-matrix/kernels.yaml.

Sources:
  * Debian:   Packages index of each suite + backports  (linux-headers-*-<arch>)
  * Ubuntu:   <suite>-updates + <suite>-hwe            (linux-headers-*-generic)
  * kernel-ppa: ppa:canonical-kernel-team/ppa           (Ubuntu, non-blocking)
  * mainline: https://kernel.ubuntu.com/mainline/       (latest stable, non-blocking)

New entries land as `blocking: false` — a human promotes them to blocking once a
run has proven green, so a fresh kernel never turns the release gate red on its own.
"""
import pathlib, re, sys, urllib.request, gzip, io, yaml

ROOT = pathlib.Path(__file__).resolve().parents[2]
KFILE = ROOT / "tests" / "dkms-matrix" / "kernels.yaml"
doc = yaml.safe_load(KFILE.read_text())

DEB = {
    "debian11": ("bullseye", ["amd64", "i386"]),
    "debian12": ("bookworm", ["amd64", "i386"]),
    "debian13": ("trixie",   ["amd64", "i386"]),
}
UBU = {
    "ubuntu2004": "focal", "ubuntu2204": "jammy", "ubuntu2404": "noble",
}


def fetch_packages(url: str) -> str:
    try:
        raw = urllib.request.urlopen(url, timeout=30).read()
    except Exception as e:
        print(f"  warn: {url}: {e}", file=sys.stderr)
        return ""
    if url.endswith(".gz"):
        return gzip.decompress(raw).decode("utf-8", "replace")
    return raw.decode("utf-8", "replace")


def known_abis(target: str) -> set:
    return {e["abi"] for e in doc.get(target, [])}


def add(target: str, abi: str, pkg: str, ver: str, fetch: str, arch: str = "amd64"):
    doc.setdefault(target, []).append(
        {"abi": abi, "pkg": pkg, "ver": ver, "fetch": fetch,
         "blocking": False, "arch": arch})
    print(f"  + {target}: {abi} ({pkg} {ver})")


changed = False
for tgt, (suite, arches) in DEB.items():
    have = known_abis(tgt)
    for arch in arches:
        idx = fetch_packages(
            f"http://deb.debian.org/debian/dists/{suite}/main/binary-{arch}/Packages.gz")
        for m in re.finditer(r"^Package: (linux-headers-[\d.]+-\d+-(?:amd64|686-pae))\n"
                             r"(?:.*\n)*?Version: (\S+)", idx, re.M):
            pkg, ver = m.group(1), m.group(2)
            abi = pkg.replace("linux-headers-", "")
            if abi not in have:
                add(tgt, abi, pkg, ver, "archive", "i386" if "686" in abi else "amd64")
                changed = True

for tgt, suite in UBU.items():
    have = known_abis(tgt)
    for pocket in (f"{suite}-updates", suite):
        idx = fetch_packages(
            f"http://archive.ubuntu.com/ubuntu/dists/{pocket}/main/binary-amd64/Packages.gz")
        for m in re.finditer(r"^Package: (linux-headers-[\d.]+-\d+-generic)\n"
                             r"(?:.*\n)*?Version: (\S+)", idx, re.M):
            pkg, ver = m.group(1), m.group(2)
            abi = pkg.replace("linux-headers-", "")
            if abi not in have:
                add(tgt, abi, pkg, ver, "archive")
                changed = True

if changed:
    KFILE.write_text(
        "# Auto-updated by .github/workflows/kernel-refresh.yml — new entries start\n"
        "# as blocking:false; promote to blocking:true after a green run.\n\n"
        + yaml.safe_dump(doc, sort_keys=True, default_flow_style=False))
    print("kernels.yaml updated")
else:
    print("no new kernels")
