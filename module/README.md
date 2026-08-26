# i2c-piix4 with ASF Host Notify (SMB0001)

Patched copy of the mainline `i2c-piix4` driver (pristine source in `../ref/`,
identical between v7.1.8 and current mainline) that adds SMBus Host Notify
reception to the auxiliary SMBus adapter on AMD FCH chipsets, using the ASF
slave function of that controller.

Why: on the ThinkPad T14 Gen 2a AMD (and siblings), the Synaptics touchpad
supports RMI4-over-SMBus (InterTouch), but `psmouse-smbus`/`rmi_smbus` refuse
to attach because no AMD adapter advertises `I2C_FUNC_SMBUS_HOST_NOTIFY`.
Windows drives the pad through the same ASF block, bound via the ACPI
`SMB0001` device (see `../PLAN.md` for the full investigation).

What it does:

- Finds the ACPI `SMB0001` device, takes the IO base + IRQ from its `_CRS`.
- If the IO base matches piix4's aux adapter, claims the rest of the 0x20-byte
  IO window (piix4 itself only requests 9 bytes), arms the ASF slave to listen
  at the SMBus Host address (0x08), and requests the (shared, level) IRQ.
- The aux adapter then advertises `I2C_FUNC_SMBUS_HOST_NOTIFY`; incoming
  Host Notify messages are decoded from the ASF data bank and forwarded via
  `i2c_handle_smbus_host_notify()`.
- Master transfers on the aux adapter are wrapped in the slave-offline /
  slave-rearm dance the hardware requires (from `i2c-amd-asf-plat.c`).

Module parameters:

- `asf_host_notify=0` — kill switch, behaves like stock i2c-piix4
- `asf_irq=N` — override the IRQ taken from ACPI (`-1` = ACPI, default)

Build (needs `linux-headers` for the running kernel):

    make

Test load (nothing persists; see PLAN.md §Verification for the full procedure):

    sudo modprobe -r psmouse
    sudo rmmod rmi_smbus i2c_piix4 2>/dev/null
    sudo insmod ./i2c-piix4.ko dyndbg=+p
    sudo modprobe psmouse

Revert: `sudo rmmod i2c_piix4 && sudo modprobe i2c_piix4` (stock), reload
psmouse — or reboot.

## Status (2026-08-25)

**Working on gondolin (7.1.9-arch1-2).** IRQ 7 shows as `7-fasteoi piix4-asf`,
`rmi4_smbus 11-002c` attaches, input device is `Synaptics TM3471-030`, TrackPoint
stays on the RMI4 PS/2 pass-through. Fast flicks and two-finger scroll are fixed.

Two hardware findings beyond the original plan were required:

1. **DATA_EN steering** — `ASFINDEX` shares port base+0x07 with `SMBBLKDAT`.
   `ASFDATABNKSEL.DATA_EN` (bit 7) must be set while mastering so block reads
   see the host FIFO rather than the ASF bank; otherwise RMI4 PDT reads return
   garbage ("Missing F01 container").
2. **IRQ trigger** — Linux's `acpi_dev_get_irqresource()` overrides the legacy
   `IRQ()` descriptor in `SMB0001._CRS` to edge/high (the ISA default), but the
   ASF block asserts a level/active-low line. The driver intercepts the IRQ
   resource in the `_CRS` walk and calls `acpi_register_gsi()` with the raw
   `_CRS` attributes. This only works for the pin's *first user*, which on a
   fresh boot is this module (nothing else references IRQ 7 in the DSDT). After
   a module reload with mismatched attributes the driver warns and asks for a
   reboot.

## Install (DKMS)

    sudo pacman -S dkms
    cd pkg && makepkg -f && sudo pacman -U i2c-piix4-asf-dkms-*.pkg.tar.zst

This builds into `/usr/lib/modules/<ver>/updates/`, which depmod prefers over
the in-tree module, and installs `/usr/lib/modprobe.d/i2c-piix4-asf.conf`
(`psmouse synaptics_intertouch=1`, softdep `rmi_smbus`). Revert:
`sudo pacman -R i2c-piix4-asf-dkms`.
