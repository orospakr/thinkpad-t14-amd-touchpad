#!/bin/bash
# tools/ci/check-kernel.sh arch|omarchy
#
# Against the one kernel whose headers are installed (or $KDIR):
#   1. as shipped: apply patches/ to the repo's pristine sources and build
#      the three modules, which is exactly what DKMS does on a user's machine;
#   2. as refreshed: refresh a scratch copy of the sources to that kernel's
#      own stable tag, then apply and build again, so a series bump shows up
#      here as a failure before it reaches a machine;
#   3. list the distribution's own kernel patches that touch the files this
#      package rebuilds (a warning, not a failure: see README "Known gap").
set -euo pipefail
label=${1:?usage: $0 arch|omarchy}
top=$(cd "$(dirname "$0")/../.." && pwd)
scratch=${SCRATCH:-$(mktemp -d)}

if [[ -z ${KDIR:-} ]]; then
  case $label in
    arch)    KDIR=$(ls -d /usr/lib/modules/*-arch*/build | head -1) ;;
    omarchy) KDIR=$(ls -d /usr/lib/modules/*-omarchy/build | head -1) ;;
    *)       KDIR=$(ls -d /usr/lib/modules/*/build | head -1) ;;
  esac
fi
kver=$(basename "$(dirname "$KDIR")")            # 7.2.3-arch1-3 / 7.2.5-3-omarchy
base=${kver%%-*}                                  # 7.2.3
tag=v$base
echo "== $label: kernel $kver (headers $KDIR), stable tag $tag, sources $(cat "$top/KERNEL_SOURCE")"

echo "== 1. as shipped: patches/ on the repo sources, built against $kver"
KDIR=$KDIR TRY_DIR=$scratch/shipped "$top/tools/try-patches.sh" build

echo "== 2. as refreshed: sources from $tag, patches/ applied and built against $kver"
rm -rf "$scratch/refreshed"; mkdir -p "$scratch/refreshed"
cp -r "$top/drivers" "$top/patches" "$top/tools" "$top/Makefile" "$top/KERNEL_SOURCE" "$scratch/refreshed/"
( cd "$scratch/refreshed" && tools/refresh-sources.sh "$tag" | grep -v '^unchanged' || true )
if diff -rq "$top/drivers" "$scratch/refreshed/drivers" >/dev/null; then
  echo "sources at $tag are identical to the repo's $(cat "$top/KERNEL_SOURCE"); build below is the same as step 1"
else
  echo "sources at $tag differ from the repo's $(cat "$top/KERNEL_SOURCE") in:"
  diff -rq "$top/drivers" "$scratch/refreshed/drivers" | sed 's/^/  /'
  echo "::warning title=refresh due::$label kernel $kver differs from KERNEL_SOURCE $(cat "$top/KERNEL_SOURCE"); a refreshed release is due"
fi
KDIR=$KDIR TRY_DIR=$scratch/refreshed-build "$scratch/refreshed/tools/try-patches.sh" build

echo "== 3. distribution patches touching the files this package rebuilds"
files=$(grep -v -E '^\s*(#|$)' "$top/tools/sources.list")
pat=$(printf '%s\n' $files | sed 's/[.]/\\./g' | paste -sd'|')
mkdir -p "$scratch/distro"
case $label in
  arch)
    rest=${kver#*-}; archtag=${rest%-*}               # arch1
    url="https://github.com/archlinux/linux/releases/download/v$base-$archtag/linux-v$base-$archtag.patch.zst"
    curl -fsSL --retry 3 -o "$scratch/distro/arch.patch.zst" "$url"
    zstd -dcq "$scratch/distro/arch.patch.zst" > "$scratch/distro/arch.patch"
    hits=$(grep -E "^diff --git a/($pat) " "$scratch/distro/arch.patch" || true)
    ;;
  omarchy)
    api=https://api.github.com/repos/omacom/omarchy-pkgs/contents/pkgbuilds/linux-omarchy
    auth=(); [[ -n ${GITHUB_TOKEN:-} ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    names=$(curl -fsSL --retry 3 "${auth[@]}" "$api" | grep -o '"name": *"[^"]*\.patch"' | sed 's/.*: *"//; s/"$//')
    hits=""
    for n in $names; do
      curl -fsSL --retry 3 -o "$scratch/distro/$n" "https://raw.githubusercontent.com/omacom/omarchy-pkgs/master/pkgbuilds/linux-omarchy/$n"
      h=$(grep -E "^diff --git a/($pat) " "$scratch/distro/$n" | sed "s/^/$n: /" || true)
      [[ -n $h ]] && hits+="$h"$'\n'
    done
    ;;
esac
if [[ -n ${hits:-} ]]; then
  echo "$hits"
  echo "::warning title=distribution patches in rebuilt files::$label kernel carries changes in files this package replaces (see README, Known gap): $(echo "$hits" | grep . | paste -sd';')"
else
  echo "none"
fi
echo "== $label: OK"
