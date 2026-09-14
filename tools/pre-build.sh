#!/bin/bash
# DKMS PRE_BUILD hook: refuse to build against a kernel series other than the
# one the pristine sources came from. A loud failure here beats a module that
# compiles from stale sources.
#
#   $1  kernel version DKMS is building for (kernelver)
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
want=$(cut -c2- "$top/KERNEL_SOURCE")          # v7.1.9 -> 7.1.9
have=${1:?kernelver}
want_series=${want%.*}                           # 7.1
have_series=${have%%-*}; have_series=${have_series%.*}
if [[ $want_series != "$have_series" ]]; then
  cat >&2 <<MSG
$(basename "$top"): sources are from kernel $want (series $want_series) but this
build is for $have (series $have_series). Refusing to build from stale sources.
Run tools/refresh-sources.sh v<version> and tools/try-patches.sh build on a
matching kernel, then release a new version.
MSG
  exit 1
fi
