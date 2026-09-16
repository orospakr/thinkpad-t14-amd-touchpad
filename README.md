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

The patches are written for upstream and carried here until they land;
see [Carried patches](#carried-patches) for where each one stands and when
it goes away. The maintainer research is in `docs/`.

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

## Carried patches

This is a carry, not a fork: every patch is aimed at a specific upstream
tree, and the package exists only until the kernels Omarchy and Arch ship
contain the same fixes. This table is the contract.

| Patch | Upstream tree | Status | Goes away when |
|---|---|---|---|
| 0001 `i2c: piix4:` SMBus Host Notify through the ASF target block on `SMB0001` platforms | linux-i2c (Andi Shyti, Jean Delvare) | Not yet posted. Will go out as an RFC that answers the 2024 review which moved AMD ASF support into `i2c-amd-asf-plat`: that driver cannot bind here because `acpi_platform.c` refuses a platform device for `SMB0001` when it has `_CRS`. | The running kernel's `i2c-piix4` (or any driver) offers `I2C_FUNC_SMBUS_HOST_NOTIFY` on the aux port. |
| 0002 `Input: synaptics-rmi4:` let the device settle after the PS/2 reset on SMBus resume | linux-input (Dmitry Torokhov) | Not yet posted. One open measurement first: whether 250 ms at the same position also works, and whether 300 ms through the existing `reset_delay_ms` does not (see `docs/SHIP-PLAN.md`). | Merged and present in the running kernel's `rmi_smbus`. |
| 0003 `Input: synaptics:` set the RMI4 doze interval Lenovo's driver uses on affected pads | linux-input | Not yet posted. | Merged and present in the running kernel's `psmouse`. |
| 0004 `Input: synaptics:` enable InterTouch on the ThinkPad T14/P14s Gen 2 AMD (`LEN2073`) | linux-input | Not yet posted; goes last, after 0001 is in, because `LEN2073` alone was tried in March 2026 and did nothing. | Merged, together with a kernel that satisfies 0001. |

The whole package is retired once a stock Omarchy or Arch kernel drives the
pad over SMBus on its own: with the package removed,
`grep Phys /proc/bus/input/devices` shows the Synaptics device on an `rmi4-`
path. Each row's status is updated as patches are posted and merged, with
the lore link in the patch file's header.

### Kernel policy

The policy is "the patches apply and the modules build". DKMS applies
`patches/` and compiles on every kernel install; if either step fails, the
DKMS hook reports it and the stock modules load, so the pad silently
returns to PS/2 and `thinkpad-t14-amd-touchpad-check` says so.
`tools/pre-build.sh` adds a warning to the DKMS log when the kernel is from
a different series than the pristine sources, because a driver from another
series can compile and still misbehave. When that warning appears a
refreshed release is due:

```sh
tools/refresh-sources.sh v7.3.2      # replace the pristine files, update KERNEL_SOURCE
tools/try-patches.sh build           # apply patches/ to a scratch copy and compile
```

then bump `PACKAGE_VERSION` and the package version and tag a release.

CI (`.github/workflows/build.yml`) does this check weekly and on every
push against three kernels: the current Arch `linux-headers`, Omarchy's
`linux-omarchy-headers`, and mainline `master`. For the two packaged
kernels it also refreshes the sources to that kernel's own tag and applies
the patches again, so a series bump shows up as a failing job before it
reaches a machine.

### Known gap: patches the distribution kernel carries in these files

The three modules are rebuilt from pristine kernel.org sources, so any
change the distribution kernel carries in the same files is dropped on that
kernel until this package refreshes to a series that contains it. CI lists
those patches. Known today: Omarchy's `linux-omarchy` carries two
psmouse hunks in `0560-input.patch` (a `protocol_handler` NULL check in
`psmouse_disconnect`, and a signed-coordinate clamp in `focaltech.c`); both
are already in mainline and arrive here with the 7.3 refresh.

## How the tree is built

`drivers/` holds unmodified files from the kernel tag named in
`KERNEL_SOURCE`, fetched one file at a time by `tools/refresh-sources.sh`
from the stable tree on git.kernel.org. `patches/` holds the four patches in
upstream format; DKMS applies them with `patch -p1` at build time, so a
patch either applies or fails loudly, and the same files are what goes to
the mailing lists.

The kernel-series policy and the refresh procedure are under
[Kernel policy](#kernel-policy) above.

Layout:

- `dkms.conf`, `Makefile`, `KERNEL_SOURCE`, `drivers/`, `patches/`, `tools/`: the DKMS source tree
- `packaging/arch/`: PKGBUILD, modprobe drop-in, install scriptlet
- `docs/`: ship plan, upstreaming notes
- `research/`: the investigation that produced the patches, with captures, harnesses and the original write-ups. Not part of the package.

## License

GPL-2.0-only, the same as the kernel files it patches. See `LICENSE`.
