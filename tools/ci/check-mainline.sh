#!/bin/bash
# tools/ci/check-mainline.sh [linux-tree]
#
# Apply patches/ to a mainline tree with git am (the upstream shape of the
# carry), build the three modules in-tree, and run checkpatch. A shallow
# clone of torvalds/linux is made in $1 (default: ./linux) when absent.
set -euo pipefail
top=$(cd "$(dirname "$0")/../.." && pwd)
tree=${1:-$top/build/linux}
if [[ ! -d $tree/.git ]]; then
  git clone --depth 1 https://github.com/torvalds/linux.git "$tree"
fi
cd "$tree"
git config user.name ci; git config user.email ci@example.invalid
git am --abort 2>/dev/null || true
git checkout -q -B carry origin/HEAD          # start from the upstream tip every run
git clean -qfd
echo "== mainline $(git log -1 --format='%h %s')"
git am "$top"/patches/*.patch
git log --oneline -4

make -s defconfig
scripts/config --enable I2C --enable I2C_SMBUS --module I2C_PIIX4 \
  --enable INPUT_MOUSE --module MOUSE_PS2 --enable MOUSE_PS2_SYNAPTICS \
  --enable MOUSE_PS2_SYNAPTICS_SMBUS --enable MOUSE_PS2_SMBUS \
  --enable MOUSE_PS2_FOCALTECH --enable MOUSE_PS2_TRACKPOINT \
  --module RMI4_CORE --module RMI4_SMB --enable RMI4_F03 --enable RMI4_F11 \
  --enable RMI4_F12 --enable RMI4_F30
make -s olddefconfig
for c in CONFIG_I2C_PIIX4 CONFIG_RMI4_SMB CONFIG_MOUSE_PS2; do
  grep -q "^$c=m" .config || { echo "$c is not =m after olddefconfig"; grep "^$c" .config || true; exit 1; }
done
make -s -j"$(nproc)" modules_prepare
# Single-module targets run modpost without vmlinux.o; unresolved kernel
# symbols are expected there and must not fail the build.
make -s -j"$(nproc)" KBUILD_MODPOST_WARN=1 drivers/i2c/busses/i2c-piix4.ko drivers/input/rmi4/rmi_smbus.ko drivers/input/mouse/psmouse.ko
ls -la drivers/i2c/busses/i2c-piix4.ko drivers/input/rmi4/rmi_smbus.ko drivers/input/mouse/psmouse.ko

echo "== checkpatch (advisory)"
./scripts/checkpatch.pl --strict --no-signoff --no-tree "$top"/patches/*.patch || true
echo "== mainline: OK"
