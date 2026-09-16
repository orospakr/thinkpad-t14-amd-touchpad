#!/bin/bash
# DKMS PRE_BUILD hook. The policy is "the patches apply and the build
# succeeds": DKMS applies patches/ and runs make, and either failing is the
# loud signal. This hook only warns when the kernel being built for is from a
# different series than the pristine sources came from, so that a build which
# happens to succeed from stale sources is at least visible in the DKMS log.
#
#   $1  kernel version DKMS is building for (kernelver)
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
want=$(cut -c2- "$top/KERNEL_SOURCE")          # v7.2.3 -> 7.2.3
have=${1:?kernelver}
want_series=${want%.*}                           # 7.2
have_series=${have%%-*}; have_series=${have_series%.*}
if [[ $want_series != "$have_series" ]]; then
  cat >&2 <<MSG
$(basename "$top"): WARNING: sources are from kernel $want (series $want_series)
but this build is for $have (series $have_series). Building anyway; if the
patches apply and the modules compile they are expected to work, but a
refreshed release (tools/refresh-sources.sh) is due. Run
thinkpad-t14-amd-touchpad-check after the next boot.
MSG
fi
exit 0
