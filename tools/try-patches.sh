#!/bin/bash
# tools/try-patches.sh [build]
#
# Copy the pristine tree to a scratch directory, apply patches/*.patch in
# order with patch -p1 exactly as DKMS does, and (with "build") compile the
# three modules against the running kernel's headers. Nothing is installed.
set -euo pipefail
top=$(cd "$(dirname "$0")/.." && pwd)
work=${TRY_DIR:-$top/build/try}
rm -rf "$work"; mkdir -p "$work"
cp -r "$top/drivers" "$top/Makefile" "$work/"
for p in "$top"/patches/*.patch; do
  echo "== $(basename "$p")"
  patch -d "$work" -p1 --no-backup-if-mismatch < "$p"
done
if [[ ${1:-} == build ]]; then
  make -C "${KDIR:-/usr/lib/modules/$(uname -r)/build}" M="$work" modules
  for m in drivers/i2c/busses/i2c-piix4.ko drivers/input/rmi4/rmi_smbus.ko drivers/input/mouse/psmouse.ko; do
    printf '%-40s %s\n' "$m" "$(modinfo -F srcversion "$work/$m")"
  done
fi
