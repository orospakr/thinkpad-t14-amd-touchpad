# thinkpad-t14-amd-touchpad

Runs the Synaptics touchpad in the ThinkPad T14 Gen 2a and P14s Gen 2 AMD
over RMI4/SMBus (InterTouch) instead of the PS/2 fallback the stock kernel
leaves it on. Three in-tree kernel modules are rebuilt by DKMS from pristine
kernel sources plus the patches in `patches/`, and installed under
`/updates` so they shadow the stock ones:

| Module | Patch | What it fixes |
|---|---|---|
| `i2c-piix4` | 0001 | The AMD FCH SMBus controller gains SMBus Host Notify through its ASF target block (ACPI `SMB0001`). Without it psmouse cannot use the SMBus path at all. |
| `rmi_smbus` | 0002 | After suspend the pad was reconfigured too soon after the PS/2 reset psmouse sends at resume, leaving it at 80 Hz or with a jump on the first touch. A 300 ms settle fixes both. |
| `psmouse` | 0003, 0004 | Sets the F01 doze interval Lenovo's Windows driver uses (short taps and two-finger touches were missed at the default), and adds `LEN2073` to the SMBus allowlist. |

On PS/2 the pad reports at 80 Hz single-finger and about 40 Hz with two
fingers; over SMBus it reports every 15 ms with two-finger gestures intact
and the TrackPoint still on its PS/2 pass-through.

The patches are written for upstream and carried here until they land.
Status and the maintainer research are in `docs/`.

## Hardware

Tested on a ThinkPad T14 Gen 2a AMD (20XL, Ryzen 5 PRO 5650U, Synaptics
TM3471, PnP `LEN2073`). Anything with the same shape should work: an AMD FCH
SMBus controller (`1022:790b`) whose ACPI `SMB0001` device describes the
second port with an IO base and IRQ, and a Synaptics pad that supports RMI4
over SMBus. Reports from other machines are welcome.

## Install

Arch Linux (and Omarchy):

```sh
git clone https://github.com/orospakr/thinkpad-t14-amd-touchpad
cd thinkpad-t14-amd-touchpad/packaging/arch
makepkg -si
reboot
thinkpad-t14-amd-touchpad-check
```

Any distribution with DKMS: copy the tree to
`/usr/src/thinkpad-t14-amd-touchpad-<version>` and run
`dkms install thinkpad-t14-amd-touchpad/<version>`. The version is the
`PACKAGE_VERSION` in `dkms.conf`.

`thinkpad-t14-amd-touchpad-check` reports whether the three modules are
installed, loaded from `/updates`, and whether the touchpad is on the RMI4
transport. Run it after every kernel update. If DKMS fails to build, the
stock modules load and the pad silently returns to PS/2; the check makes
that visible.

## Remove

```sh
sudo pacman -Rns thinkpad-t14-amd-touchpad-dkms   # or: dkms remove thinkpad-t14-amd-touchpad/<version> --all
reboot
```

DKMS restores the stock modules it replaced.

## How the tree is built

`drivers/` holds unmodified files from the kernel tag named in
`KERNEL_SOURCE`, fetched one file at a time by `tools/refresh-sources.sh`
from the stable tree on git.kernel.org. `patches/` holds the four patches in
upstream format; DKMS applies them with `patch -p1` at build time, so a
patch either applies or fails loudly, and the same files are what goes to
the mailing lists.

`tools/pre-build.sh` refuses to build against a kernel from a different
series than the sources came from, because a copied driver from another
series can compile and still misbehave. When Arch moves to a new series:

```sh
tools/refresh-sources.sh v7.2.4      # replace the pristine files, update KERNEL_SOURCE
tools/try-patches.sh build           # apply patches/ to a scratch copy and compile
```

then bump `PACKAGE_VERSION` and the package version and tag a release.

Layout:

- `dkms.conf`, `Makefile`, `KERNEL_SOURCE`, `drivers/`, `patches/`, `tools/`: the DKMS source tree
- `packaging/arch/`: PKGBUILD, modprobe drop-in, install scriptlet
- `docs/`: ship plan, upstreaming notes
- `research/`: the investigation that produced the patches, with captures, harnesses and the original write-ups. Not part of the package.

## License

GPL-2.0-only, the same as the kernel files it patches. See `LICENSE`.
