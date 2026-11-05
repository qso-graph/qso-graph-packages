#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# scripts/linux-repos.sh, run as the Packages workflow runs it, on packages for two products made here,
# signed with a key made here for the test and thrown away: never the release key. Needs rpm, rpmbuild,
# createrepo_c, apt-ftparchive, dpkg-deb, gpg and curl (Ubuntu: rpm createrepo-c apt-utils gnupg curl).
#
#   scripts/test-linux-repos.sh
#
# Proves: both products' packages are in both repositories, every .rpm and index is signed and
# verifies, dnf's and apt's files are where Desktop's users have them and under QSO Graph's names too,
# the apt Label is unchanged, a package already served is kept byte for byte on rpm 4 and rpm 6, and
# a served copy of another package or a file for no listed product is not taken (planted cases).
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
SIGNING_KEY="$key" PASSPHRASE_FILE="$pass" PACKAGES_BASE="file://$work/served" SIGNED_LIST="$work/signed" \
  bash "$here/scripts/linux-repos.sh" "$products" "$in" "$out"

fail() { echo "✗ $*" >&2; exit 1; }
# dnf's primary index, however this createrepo_c compressed it (gzip, zstd, xz or bzip2).
primary() {
  local file
  file=$(find "$1/repodata" -name '*primary.xml*' | head -1)
  case "$file" in
    *.gz) zcat "$file" ;;
    *.zst) zstd -dc "$file" ;;
    *.xz) xzcat "$file" ;;
    *.bz2) bzcat "$file" ;;
    *) fail "no primary index in $1/repodata" ;;
  esac
}
for name in qso-graph-one qso-graph-two; do
  for arch in x86_64 aarch64; do
    [ -f "$out/rpm/$arch/$name-1.0.0-linux-$arch.rpm" ] || fail "$name $arch .rpm not in dnf's repository"
    grep -q "<name>$name</name>" <(primary "$out/rpm/$arch") || fail "$name not in $arch's index"
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
# Every .rpm carries a v4 header signature, the one rpm 4 reads (RHEL and Rocky 9): rpm 6 alone makes
# only a v6 one, which dnf there called "not signed". And each signed one is listed for the upload.
for f in "$out"/rpm/*/*.rpm; do
  [[ $(rpm -qp --qf '%{RSAHEADER:pgpsig}' "$f" 2>/dev/null) =~ ^RSA/ ]] || fail "$(basename "$f") has no v4 signature"
done
[ "$(LC_ALL=C sort "$work/signed")" = "$(cd "$out" && find rpm -name '*.rpm' | LC_ALL=C sort)" ] \
  || fail "the signed list is not the .rpm files signed: $(cat "$work/signed")"
echo "✓ two products in apt and dnf, signed, under both names"

# Built again with that repository served: every .rpm is kept as served, byte for byte, so dnf's index
# names the files that are there (#143). A signature carries its time, so signing again would differ.
SIGNING_KEY="$key" PASSPHRASE_FILE="$pass" PACKAGES_BASE="file://$out" SIGNED_LIST="$work/again.signed" \
  bash "$here/scripts/linux-repos.sh" "$products" "$in" "$work/again" > "$work/again.log"
[ ! -s "$work/again.signed" ] || fail "kept packages listed as signed: $(cat "$work/again.signed")"
for name in qso-graph-one qso-graph-two; do
  for arch in x86_64 aarch64; do
    file="rpm/$arch/$name-1.0.0-linux-$arch.rpm"
    grep -qxF "Kept as served: $(basename "$file")" "$work/again.log" || fail "$file signed again, not kept"
    cmp -s "$out/$file" "$work/again/$file" || fail "$file differs from the served copy"
  done
done
echo "✓ packages already served are kept, byte for byte"

# Planted: a served copy that is not this release's package is signed anew, not kept.
mkdir -p "$work/other/rpm/x86_64"
cp "$out/rpm/aarch64/qso-graph-one-1.0.0-linux-aarch64.rpm" "$work/other/rpm/x86_64/qso-graph-one-1.0.0-linux-x86_64.rpm"
SIGNING_KEY="$key" PASSPHRASE_FILE="$pass" PACKAGES_BASE="file://$work/other" \
  bash "$here/scripts/linux-repos.sh" "$products" "$in" "$work/other-out" > "$work/other.log"
grep -qxF 'Signed: qso-graph-one-1.0.0-linux-x86_64.rpm' "$work/other.log" || fail "another package was kept as this one"
echo "✓ a served copy of another package is not kept"

# Planted: a served copy of this very package without a v4 signature (as rpm 6 alone signs, or not
# signed at all) is signed anew and listed, so the upload rewrites it.
mkdir -p "$work/unsigned/rpm/x86_64"
cp "$in/qso-graph-two-1.0.0-linux-x86_64.rpm" "$work/unsigned/rpm/x86_64/"
SIGNING_KEY="$key" PASSPHRASE_FILE="$pass" PACKAGES_BASE="file://$work/unsigned" SIGNED_LIST="$work/unsigned.signed" \
  bash "$here/scripts/linux-repos.sh" "$products" "$in" "$work/unsigned-out" > "$work/unsigned.log"
grep -qxF 'Signed: qso-graph-two-1.0.0-linux-x86_64.rpm' "$work/unsigned.log" || fail "a served copy without a v4 signature was kept"
grep -qxF 'rpm/x86_64/qso-graph-two-1.0.0-linux-x86_64.rpm' "$work/unsigned.signed" || fail "a package signed anew is not listed for the upload"
echo "✓ every .rpm has a v4 signature, and one served without it is signed anew and rewritten"

# Planted: a file for a product products.tsv does not list is refused.
cp "$in/qso-graph-one-1.0.0-linux-amd64.deb" "$in/qso-graph-stray-1.0.0-linux-amd64.deb"
if SIGNING_KEY="$key" PASSPHRASE_FILE="$pass" PACKAGES_BASE="file://$work/served" \
  bash "$here/scripts/linux-repos.sh" "$products" "$in" "$work/repo2" 2>"$work/err"; then
  fail "a file for no listed product was taken"
fi
grep -q 'holds files for no product' "$work/err" || fail "refused for the wrong reason: $(cat "$work/err")"
echo "✓ a file for no listed product is refused"
