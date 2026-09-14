#!/bin/bash
# tools/refresh-sources.sh <tag>
#
# Replace the pristine kernel files listed in tools/sources.list with the
# copies from the stable kernel tree at <tag> (for example v7.2.4), one file
# at a time from git.kernel.org, and record the tag in KERNEL_SOURCE.
# Then check that every patch in patches/ still applies:
#
#     tools/refresh-sources.sh v7.2.4 && tools/try-patches.sh
set -euo pipefail
tag=${1:?usage: $0 <kernel tag, e.g. v7.1.9>}
top=$(cd "$(dirname "$0")/.." && pwd)
base="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain"
while read -r path; do
  [[ -z $path || $path == \#* ]] && continue
  mkdir -p "$top/$(dirname "$path")"
  tmp=$(mktemp)
  if ! curl -fsSL -o "$tmp" "$base/$path?h=$tag"; then
    echo "fetch failed: $path at $tag" >&2; rm -f "$tmp"; exit 1
  fi
  if [[ -f $top/$path ]] && cmp -s "$tmp" "$top/$path"; then
    echo "unchanged  $path"; rm -f "$tmp"
  else
    mv "$tmp" "$top/$path"; echo "updated    $path"
  fi
done < "$top/tools/sources.list"
echo "$tag" > "$top/KERNEL_SOURCE"
echo "KERNEL_SOURCE = $tag"
