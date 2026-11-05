#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# scripts/linux-repos.sh, run as the Packages workflow runs it, on packages for two products made here,
# signed with a key made here for the test and thrown away: never the release key. Needs rpm, rpmbuild,
# createrepo_c, apt-ftparchive, dpkg-deb and gpg (Ubuntu: rpm createrepo-c apt-utils gnupg).
#
#   scripts/test-linux-repos.sh
#
# Proves: both products' packages are in both repositories, every .rpm and index is signed and
# verifies, dnf's and apt's files are where Desktop's users have them and under QSO Graph's names too,
# the apt Label is unchanged, and a file for no listed product is refused (a planted case).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
install -d -m 0700 "$GNUPGHOME"
pass="$work/passphrase"
printf 'test only' > "$pass"
gpg --batch --quiet --pinentry-mode loopback --passphrase-file "$pass" \
  --quick-gen-key 'Packages test key (thrown away) <test@example.invalid>' rsa2048 sign 1d
key=$(gpg --batch --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')

products="$work/products.tsv"
printf '# test\nqso-graph/one  qso-graph-one  no\nqso-graph/two  qso-graph-two  no\n' > "$products"

# A tiny .deb and .rpm for each product, each architecture, named as releases name them.
in="$work/in"
mkdir -p "$in"
for name in qso-graph-one qso-graph-two; do
  for pair in amd64:x86_64 arm64:aarch64; do
    deb=${pair%:*} rpmarch=${pair#*:}
    root="$work/deb-$name-$deb"
    mkdir -p "$root/DEBIAN" "$root/usr/share/doc/$name"
    printf 'Package: %s\nVersion: 1.0.0\nArchitecture: %s\nMaintainer: test <test@example.invalid>\nDescription: test\n test\n' \
      "$name" "$deb" > "$root/DEBIAN/control"
    echo test > "$root/usr/share/doc/$name/README"
    dpkg-deb --root-owner-group --build "$root" "$in/$name-1.0.0-linux-$deb.deb" >/dev/null
    top="$work/rpmbuild-$name-$rpmarch"
    mkdir -p "$top/SPECS"
    cat > "$top/SPECS/$name.spec" <<SPEC
Name: $name
Version: 1.0.0
Release: 1
Summary: test
License: GPL-3.0-only
%description
test
%install
mkdir -p %{buildroot}/usr/share/doc/$name
echo test > %{buildroot}/usr/share/doc/$name/README
%files
/usr/share/doc/$name/README
SPEC
    rpmbuild --quiet --define "_topdir $top" --target "$rpmarch" -bb "$top/SPECS/$name.spec" >/dev/null 2>&1
    cp "$top"/RPMS/"$rpmarch"/*.rpm "$in/$name-1.0.0-linux-$rpmarch.rpm"
  done
done

# Nothing is served yet: no copy to keep.
mkdir -p "$work/served"
out="$work/repo"
SIGNING_KEY="$key" PASSPHRASE_FILE="$pass" PACKAGES_BASE="file://$work/served" \
  bash "$here/scripts/linux-repos.sh" "$products" "$in" "$out"

fail() { echo "✗ $*" >&2; exit 1; }
for name in qso-graph-one qso-graph-two; do
  for arch in x86_64 aarch64; do
    [ -f "$out/rpm/$arch/$name-1.0.0-linux-$arch.rpm" ] || fail "$name $arch .rpm not in dnf's repository"
    grep -q "<name>$name</name>" <(zcat "$out"/rpm/"$arch"/repodata/*-primary.xml.gz) || fail "$name not in $arch's index"
  done
  for arch in amd64 arm64; do
    grep -q "^Package: $name$" "$out/apt/dists/stable/main/binary-$arch/Packages" || fail "$name not in apt's $arch index"
  done
done
for f in qso-graph.asc qso-graph.gpg qso-graph.repo qso-graph-desktop.asc qso-graph-desktop.gpg qso-graph-desktop.repo; do
  [ -s "$out/$f" ] || fail "$f missing"
done
grep -q '^Label: QSO Graph Desktop$' "$out/apt/dists/stable/Release" || fail "the apt Label changed"
grep -q '^\[qso-graph\]$' "$out/qso-graph.repo" || fail "qso-graph.repo"
grep -qF 'baseurl=https://packages.qso-graph.net/rpm/$basearch' "$out/qso-graph-desktop.repo" || fail "qso-graph-desktop.repo's baseurl"
grep -qF 'gpgkey=https://packages.qso-graph.net/qso-graph-desktop.asc' "$out/qso-graph-desktop.repo" || fail "qso-graph-desktop.repo's key"
gpg --batch --verify "$out/apt/dists/stable/InRelease" 2>/dev/null || fail "InRelease"
echo "✓ two products in apt and dnf, signed, under both names"

# Planted: a file for a product products.tsv does not list is refused.
cp "$in/qso-graph-one-1.0.0-linux-amd64.deb" "$in/qso-graph-stray-1.0.0-linux-amd64.deb"
if SIGNING_KEY="$key" PASSPHRASE_FILE="$pass" PACKAGES_BASE="file://$work/served" \
  bash "$here/scripts/linux-repos.sh" "$products" "$in" "$work/repo2" 2>"$work/err"; then
  fail "a file for no listed product was taken"
fi
grep -q 'holds files for no product' "$work/err" || fail "refused for the wrong reason: $(cat "$work/err")"
echo "✓ a file for no listed product is refused"
