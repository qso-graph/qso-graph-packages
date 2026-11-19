#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Release tags on stdin, one a line; prints those at or after <since>, in the order given.
#
#   scripts/served-since.sh <since> < tags
#
# <since> is products.tsv's fourth column: the first release whose packages carry the product's package
# name. Releases before it were packaged under another name, so their files cannot be found under this
# one. "-" serves every release. Every tag must be vX.Y.Z; anything else is refused, not skipped.
set -euo pipefail

since=${1:?usage: served-since.sh <since> < tags}
[ "$since" = - ] || [[ $since =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a release tag: since $since" >&2; exit 1; }

while read -r tag; do
  [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Not a release tag: $tag" >&2; exit 1; }
  if [ "$since" = - ] || printf '%s\n' "${since#v}" "${tag#v}" | sort -V -C; then
    echo "$tag"
  else
    echo "– $tag: before $since, packaged under another name" >&2
  fi
done
