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

## Status (2026-08-27)

**Working on gondolin (7.1.9-arch1-2), reviewed, S3-tested.** IRQ 7 shows as
`7-fasteoi piix4-asf`, `rmi4_smbus 11-002c` attaches, input device is
`Synaptics TM3471-030`, TrackPoint stays on the RMI4 PS/2 pass-through (F03).
Touchpad reports at ~67 Hz single-finger (15 ms, tight), TrackPoint at ~140 Hz;
both were capped by the shared PS/2 link before. Survives S3 (`deep`) suspend.

Hardware findings beyond the original plan:

1. **DATA_EN steering** — `ASFINDEX` shares port base+0x07 with `SMBBLKDAT`.
   `ASFDATABNKSEL.DATA_EN` (bit 7) must be set while mastering so block reads
   see the host FIFO rather than the ASF bank; otherwise RMI4 PDT reads return
   garbage ("Missing F01 container").
2. **IRQ trigger** — Linux's `acpi_dev_get_irqresource()` overrides the legacy
   `IRQ()` descriptor in `SMB0001._CRS` to edge/high (the ISA default), but the
   ASF block asserts a level/active-low line. The driver intercepts the IRQ
   resource in the `_CRS` walk and calls `acpi_register_gsi()` with the raw
   `_CRS` attributes, after validating the device is ours. This only works for
   the pin's *first user*, which on a fresh boot is this module (nothing else
   references IRQ 7 in the DSDT). If beaten to the pin the driver warns and
   leaves Host Notify off.
3. **Bus collisions with the pad's own Host Notify** — the touchpad is a second
   SMBus master. About 1–2 times a minute of active use it starts a Host Notify
   exactly when the host starts a read: `piix4_transaction` reports a bus
   collision (-EIO) or the pad NAKs the address (-ENXIO), and RMI4 drops a
   report ("Failed to read object data"). Every build showed ~5 such failures
   per 3 minutes until `piix4_access_asf()` learned to yield: listen for 1 ms
   so the notify lands in a bank, drain it, retry (≤3×). Now 0 failures per
   3 minutes, ~1 retry per 2 minutes.

Review history: eight `codex exec` passes as a skeptical upstream reviewer
(`review*-out.md` in the scratch notes). Folded in: CONFIG_ACPI guard, GSI
registered only after validation and unregistered on teardown, full
firmware-state save/restore, W1C-safe `ASFDATABNKSEL` writes, start/stop
lifecycle around adapter registration, Host Notify delivery outside the
hardware mutex and fenced against adapter removal, PM suspend/resume +
shutdown hooks, AMDI001A exclusion, `-EAGAIN` for bus collision (retry only
arbitration loss / NAK), IRQ thread that resets the slave only when a bank
flag survives a full drain, drains that re-read refilled banks, fair bank
selection when both flags are set, notify storage sized for two drains.

Design positions taken (reviewer still lists these as upstream blockers):

- **Duplicates over loss.** A stuck FULL flag means a message is delivered
  twice, never dropped. Host Notify carries no payload to Linux clients, so a
  bounded duplicate is a spurious "go look" — the reviewer agrees this is a
  defensible at-least-once tradeoff, not a universal guarantee.
- **Wedge recovery is best-effort.** The reset path (LISTN off → final drain
  → SLV_RST → re-arm) has theoretical loss windows: a reception ACKed during
  the muxed PM-region wait, and an in-flight transaction that completes after
  the final drain (LISTN-off is not a completion fence; whether `ASFSTA[6]`
  latches while `SLV_INTR` is masked is undocumented, `SlaveBusy` semantics
  likewise). It has never fired on this hardware (0 wedge resets in every
  3-minute run), so these are documented rather than engineered around.
- **Generic `-ENXIO` yield.** A NAK during a transfer is retried after a 1 ms
  listen window because the pad NAKs when it is about to notify. This costs
  absent-address probes ~4–7 ms; acceptable for the aux adapter, would need
  narrowing (or evidence gating) upstream.
- **Frame length `>= 3`** rather than exactly 3 (PEC byte tolerance).

Open questions carried forward: `SMB0001` ownership vs `i2c-scmi`, the
first-user GSI trick vs a proper `resource.c` override, DMI/platform gating,
splitting the `-EAGAIN` change into a prerequisite patch, Kconfig text,
adapter-private data instead of the global `piix4_asf`.

## Testing

`test-cycle.sh` (run as root): `load [path.ko]` swaps the module in and
re-attaches RMI4, `measure` captures 5 s of one-finger motion and prints the
report-interval distribution plus the RMI4 error count, `status` prints the
IRQ line, input names and recent ASF/RMI4 dmesg. Judge a build by a 3-minute
active-use run with `module i2c_piix4 format "collision" +p` /
`format "no response" +p` / `format "lost the bus" +p` in dynamic debug —
30 s samples are too short to see the ~1/min bus-loss events.

## Install (DKMS)

    sudo pacman -S dkms
    cd pkg && makepkg -f && sudo pacman -U i2c-piix4-asf-dkms-*.pkg.tar.zst

This builds into `/usr/lib/modules/<ver>/updates/`, which depmod prefers over
the in-tree module, and installs `/usr/lib/modprobe.d/i2c-piix4-asf.conf`
(`psmouse synaptics_intertouch=1`, softdep `rmi_smbus`). Revert:
`sudo pacman -R i2c-piix4-asf-dkms`.
