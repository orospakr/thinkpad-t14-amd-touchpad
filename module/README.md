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
