#!/bin/sh
# Runs inside a clean debian:trixie container for build-reprotest.
# Expects: the .dsc + orig + debian tarballs in /b, $OUTDIR set (A or B).
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  dpkg-dev debhelper dh-dkms build-essential xz-utils ca-certificates
cd /b
apt-get build-dep -y -qq ./nvidia-legacy-*.dsc
dpkg-source --no-check -x nvidia-legacy-*.dsc /tmp/x
cd /tmp/x
dpkg-buildpackage -b -uc -us
mkdir -p "/b/$OUTDIR"
cp /tmp/*.deb "/b/$OUTDIR/"
ls -la "/b/$OUTDIR/"
