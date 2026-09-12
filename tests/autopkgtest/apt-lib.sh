#!/bin/sh
# Shared apt helpers, sourced by run.sh and by the individual test scripts
# it execs inside the container (file-conflicts.sh, xorg-dummy.sh,
# install-purge.sh). All run against a throwaway, single-use container.

# Exclude the *-security pocket (Debian) / *-security suite (Ubuntu)
# entirely: it has repeatedly served 404s on files its own Packages index
# still lists (Fastly-CDN-edge cache staleness upstream, not ours --
# confirmed by hitting different offending packages, different edge IPs,
# on different runs/hosts). These disposable containers do not need
# CVE-patched versions.
apt_disable_security_pocket() {
  printf "Package: *\nPin: release a=*-security\nPin-Priority: -1\n" \
    > /etc/apt/preferences.d/no-security
}

# apt-get install wrapper that recovers from:
#   "pkgA : Depends: pkgB (= X) but Y is to be installed"
# -- caused by the base image shipping pkgB already at a (now pinned-out)
# security version, while pkgA's only remaining candidate needs the
# main-pocket version of pkgB. Retries, forcing each named pkgB back to the
# plain-suite pocket, until the transaction succeeds or attempts run out.
# Silent on success; on final failure the apt output goes to stderr, so it
# survives even if a caller redirects our stdout (e.g. `>/dev/null`).
apt_install_reconciled() {
  extra=""
  attempt=1
  while [ "$attempt" -le 5 ]; do
    if out="$(apt-get install -y --no-install-recommends --allow-downgrades $extra "$@" 2>&1)"; then
      return 0
    fi
    newpins="$(printf '%s\n' "$out" | grep -oP 'Depends: \K\S+(?= \(= )' | sort -u)"
    if [ -z "$newpins" ]; then
      echo "$out" >&2
      return 1
    fi
    codename="$(. /etc/os-release; echo "$VERSION_CODENAME")"
    for p in $newpins; do
      case " $extra " in
        *" $p/$codename "*) ;;
        *) extra="$extra $p/$codename" ;;
      esac
    done
    attempt=$((attempt + 1))
  done
  echo "$out" >&2
  return 1
}
