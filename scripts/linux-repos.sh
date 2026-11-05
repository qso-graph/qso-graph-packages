#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# QSO Graph's signed apt and dnf repositories, built from every product's Stable releases' .deb and
# .rpm files (first built in qso-graph-desktop, #113 there):
#
#   scripts/linux-repos.sh <products.tsv> <packages-dir> <repo-dir>
#
# <packages-dir> holds the releases' Linux packages, <package>-<version>-linux-*.deb|rpm, for the
# packages products.tsv names and no others. The repository is written to <repo-dir>, new or empty,
# laid out as packages.qso-graph.net serves it:
#   rpm/x86_64/, rpm/aarch64/   each .rpm signed with rpmsign; createrepo_c's metadata, repomd.xml
#                               signed (repomd.xml.asc), for gpgcheck and repo_gpgcheck both
#   apt/pool/main/              the .deb files
#   apt/dists/stable/           Packages for amd64 and arm64; Release, signed as InRelease and Release.gpg
#   qso-graph.asc               the release key, armoured, for dnf's gpgkey= and for people
#   qso-graph.gpg               the same key, binary, for apt's signed-by=
#   qso-graph.repo              the file dnf users put in /etc/yum.repos.d/
#   qso-graph-desktop.*         the same three under the names Desktop's users were given, which keep
#                               working: the repositories are the same, every product in them
#
# Signed with the release key, and only that key: SIGNING_KEY is its fingerprint,
# and the run stops unless the keyring in GNUPGHOME holds a secret key with exactly that fingerprint.
# PASSPHRASE_FILE holds its passphrase. The key itself is the caller's to import; nothing here prints it.
set -euo pipefail

products=${1:?usage: linux-repos.sh <products.tsv> <packages-dir> <repo-dir>}
in=${2:?usage: linux-repos.sh <products.tsv> <packages-dir> <repo-dir>}
out=${3:?usage: linux-repos.sh <products.tsv> <packages-dir> <repo-dir>}
key=${SIGNING_KEY:?SIGNING_KEY: the fingerprint of the release key}
pass=${PASSPHRASE_FILE:?PASSPHRASE_FILE: a file holding its passphrase}
[[ $key =~ ^[0-9A-F]{40}$ ]] || { echo "SIGNING_KEY is not a fingerprint: $key" >&2; exit 2; }
base=https://packages.qso-graph.net

# The key in the keyring is the release key, and it can sign.
have=$({ gpg --batch --with-colons --list-secret-keys "$key" 2>/dev/null || true; } | awk -F: '$1 == "fpr" { print $10; exit }')
[ "$have" = "$key" ] || { echo "The keyring holds no secret key $key." >&2; exit 1; }
echo "Signing with $key"
sign=(gpg --batch --yes --pinentry-mode loopback --passphrase-file "$pass" --local-user "$key")

# The packages products.tsv names: each a lower-case name, as Debian and Fedora allow.
mapfile -t names < <(awk '!/^[[:space:]]*(#|$)/ { print $2 }' "$products")
[ ${#names[@]} -gt 0 ] || { echo "$products names no package." >&2; exit 1; }
for name in "${names[@]}"; do
  [[ $name =~ ^[a-z0-9][a-z0-9.+-]+$ ]] || { echo "Not a package name: $name" >&2; exit 1; }
done
shopt -s nullglob
debs=() rpms=()
for name in "${names[@]}"; do
  debs+=("$in/$name"-[0-9]*-linux-*.deb)
  rpms+=("$in/$name"-[0-9]*-linux-*.rpm)
done
[ ${#debs[@]} -gt 0 ] && [ ${#rpms[@]} -gt 0 ] || { echo "No .deb or no .rpm in $in." >&2; exit 1; }
# Nothing else is in the folder: a file for no product listed is a mistake, not a package to offer.
all=("$in"/*)
[ ${#all[@]} -eq $((${#debs[@]} + ${#rpms[@]})) ] || { echo "$in holds files for no product in $products." >&2; exit 1; }

mkdir -p "$out"
[ -z "$(ls -A "$out")" ] || { echo "$out is not empty: give a new or empty folder." >&2; exit 1; }

# dnf. Each .rpm signed in a copy: the release's own file is left as CI built it.
#
# A package already served is kept, not signed again (#143). A signature carries the time it was
# made, so signing anew gives a file of the same size and different bytes: the upload, which never
# rewrites a package, kept the old one, and the index named the new one. dnf refused every package
# but the newest after the first rebuild, and the newest too when Promote ran twice. The served copy
# is kept only if it is this release's package (header and payload digests equal) and carries a
# signature that verifies against the release key; anything else is signed here as before.
served_base=${PACKAGES_BASE:-$base}
[[ $served_base =~ ^(https|file):// ]] || { echo "PACKAGES_BASE is not https:// or file://: $served_base" >&2; exit 2; }
rpmdb=$(mktemp -d)
trap 'rm -rf "$rpmdb"' EXIT
gpg --batch --armor --export "$key" > "$rpmdb/release-key.asc"
rpm --dbpath "$rpmdb" --import "$rpmdb/release-key.asc"
contents() { rpm -qp --qf '%{SHA256HEADER} %{PAYLOADDIGEST}' "$1" 2>/dev/null; }
for arch in x86_64 aarch64; do mkdir -p "$out/rpm/$arch"; done
for file in "${rpms[@]}"; do
  name=$(basename "$file")
  case "$name" in
    *-linux-x86_64.rpm) arch=x86_64 ;;
    *-linux-aarch64.rpm) arch=aarch64 ;;
    *) echo "An .rpm for no architecture we serve: $name" >&2; exit 1 ;;
  esac
  dest="$out/rpm/$arch/$name"
  if curl -fsS --retry 3 --proto '=https,file' -o "$dest" "$served_base/rpm/$arch/$name" 2>/dev/null \
    && [ -n "$(contents "$file")" ] && [ "$(contents "$dest")" = "$(contents "$file")" ] \
    && rpm --dbpath "$rpmdb" --checksig "$dest" 2>/dev/null | grep -q 'digests signatures OK'; then
    echo "Kept as served: $name"
    continue
  fi
  cp "$file" "$dest"
  echo "Signed: $name"
  rpmsign --addsign \
    --define "__gpg $(command -v gpg)" \
    --define "_gpg_name $key" \
    --define "_gpg_sign_cmd_extra_args --batch --pinentry-mode loopback --passphrase-file $pass" \
    "$out/rpm/$arch/$name" >/dev/null
done
for arch in x86_64 aarch64; do
  createrepo_c --quiet "$out/rpm/$arch"
  "${sign[@]}" --armor --detach-sign --output "$out/rpm/$arch/repodata/repomd.xml.asc" "$out/rpm/$arch/repodata/repomd.xml"
done

# apt: one suite, stable, one component, main.
mkdir -p "$out/apt/pool/main"
cp "${debs[@]}" "$out/apt/pool/main/"
# Until 0.5.1 the package was named qg-desktop (#145). dnf follows the rpm's Obsoletes by itself; apt
# never moves to a renamed package, so while a release under the old name is offered, so is an empty
# qg-desktop that depends on qso-graph-desktop: `apt upgrade` updates qg-desktop, which brings
# qso-graph-desktop. Built the same, byte for byte, every run (fixed times, owner and modes): a
# package already served is never rewritten (#143), so a rebuilt one would not match its index.
transitional=0
named() { for file in "${debs[@]}"; do if [ "$(dpkg-deb -f "$file" Package)" = "$1" ]; then echo "$file"; fi; done; }
if [ -n "$(named qg-desktop)" ]; then
  for arch in amd64 arm64; do
    newest=$(named qso-graph-desktop | while read -r file; do
      if [ "$(dpkg-deb -f "$file" Architecture)" = "$arch" ]; then dpkg-deb -f "$file" Version; fi; done | sort -V | tail -1)
    [ -n "$newest" ] || continue
    root=$(mktemp -d)
    mkdir -m 0755 "$root/DEBIAN"
    cat > "$root/DEBIAN/control" <<EOF
Package: qg-desktop
Version: $newest
Architecture: $arch
Maintainer: QSO Graph contributors <maintainers@qso-graph.io>
Depends: qso-graph-desktop (>= $newest)
Section: oldlibs
Priority: optional
Description: transitional package for qso-graph-desktop
 QSO Graph Desktop's package is now named qso-graph-desktop. This empty
 package moves an installation made under the old name, and can be removed.
EOF
    chmod 0755 "$root"; chmod 0644 "$root/DEBIAN/control"
    find "$root" -exec touch -h -d @0 {} +
    SOURCE_DATE_EPOCH=0 dpkg-deb --root-owner-group -Zxz --build "$root" "$out/apt/pool/main/qg-desktop_${newest}_${arch}.deb" >/dev/null
    rm -rf "$root"
    transitional=$((transitional + 1))
  done
fi
# Every package listed once, then split by architecture: apt-ftparchive's --arch lists nothing for
# these files.
(cd "$out/apt" && apt-ftparchive packages pool/main) > "$out/apt/Packages.all"
listed=0
for arch in amd64 arm64; do
  dir="$out/apt/dists/stable/main/binary-$arch"
  mkdir -p "$dir"
  awk -v arch="$arch" 'BEGIN { RS = ""; ORS = "\n\n" } $0 ~ ("\nArchitecture: " arch "\n") { print }' \
    "$out/apt/Packages.all" > "$dir/Packages"
  listed=$((listed + $(grep -c '^Package: ' "$dir/Packages" || true)))
  gzip -9nk "$dir/Packages"
done
rm "$out/apt/Packages.all"
[ "$listed" -eq $((${#debs[@]} + transitional)) ] || { echo "The apt index lists $listed packages of $((${#debs[@]} + transitional))." >&2; exit 1; }
# The Label stays what Desktop's users' apt first saw: apt refuses a repository whose Label changes
# until each user runs `apt update --allow-releaseinfo-change`.
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="QSO Graph" \
  -o APT::FTPArchive::Release::Label="QSO Graph Desktop" \
  -o APT::FTPArchive::Release::Suite=stable \
  -o APT::FTPArchive::Release::Codename=stable \
  -o APT::FTPArchive::Release::Architectures="amd64 arm64" \
  -o APT::FTPArchive::Release::Components=main \
  release "$out/apt/dists/stable" > "$out/apt/dists/stable/Release.tmp"
mv "$out/apt/dists/stable/Release.tmp" "$out/apt/dists/stable/Release"
"${sign[@]}" --clearsign --output "$out/apt/dists/stable/InRelease" "$out/apt/dists/stable/Release"
"${sign[@]}" --armor --detach-sign --output "$out/apt/dists/stable/Release.gpg" "$out/apt/dists/stable/Release"

# The key, and dnf's repository file: under QSO Graph's names, and under the names Desktop's users
# were given, which keep working.
for stem in qso-graph qso-graph-desktop; do
  gpg --batch --armor --export "$key" > "$out/$stem.asc"
  gpg --batch --export "$key" > "$out/$stem.gpg"
done
repo_file() {
  printf '[%s]\nname=%s\nbaseurl=%s/rpm/$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=%s/%s.asc\n' \
    "$1" "$2" "$base" "$base" "$1" > "$out/$1.repo"
}
repo_file qso-graph "QSO Graph"
repo_file qso-graph-desktop "QSO Graph Desktop"

# Each signature verifies, before anything is uploaded.
gpg --batch --verify "$out/apt/dists/stable/InRelease" 2>/dev/null
gpg --batch --verify "$out/apt/dists/stable/Release.gpg" "$out/apt/dists/stable/Release" 2>/dev/null
for arch in x86_64 aarch64; do
  gpg --batch --verify "$out/rpm/$arch/repodata/repomd.xml.asc" "$out/rpm/$arch/repodata/repomd.xml" 2>/dev/null
done
db=$(mktemp -d)
rpm --dbpath "$db" --import "$out/qso-graph.asc"
for file in "$out"/rpm/*/*.rpm; do
  rpm --dbpath "$db" --checksig "$file" | grep -q 'digests signatures OK' || { echo "Not signed: $file" >&2; exit 1; }
done
rm -rf "$db"
echo "Built $out: ${#rpms[@]} .rpm, ${#debs[@]} .deb, every signature verified."
