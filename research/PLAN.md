# Enable RMI4/InterTouch touchpad via ASF Host Notify (ThinkPad T14 Gen 2a, AMD Cezanne)

## Context

gondolin (ThinkPad T14 Gen 2a AMD, type 20XL, FCH SMBus `1022:790b` rev 0x51 "KERNCZ") runs its
Synaptics touchpad (PNP `LEN2073`, board id 3471) in PS/2 fallback: ~80 Hz single-finger, ~40 Hz
two-finger. Symptoms: laggy pointer, chunky no-glide scrolling, and the fastest two-finger flicks
whiffing into pointer motion (second finger never reported, so no client sees a scroll).

The pad supports RMI4-over-SMBus ("InterTouch"), but Linux can't attach it: `psmouse-smbus.c` and
`rmi_smbus.c` both require an i2c adapter advertising `I2C_FUNC_SMBUS_HOST_NOTIFY`, and no AMD
SMBus adapter provides it. Hence `SMbus companion is not ready yet` and PS/2 fallback.

### Facts established during investigation (2026-08-20)

- **Windows reference**: Lenovo's Synaptics UltraNav package (`r1mst13w.exe`, v19.5.19.95) contains
  `SynAMDSmbDrv.inf`, which binds **`ACPI\SMB0001`** and installs `Smb_driver_AMDASFUWP.sys`. So on
  this exact machine Windows drives the pad over the ASF-capable SMBus block. Artifacts in
  `artifacts/windows-driver/`.
- **ACPI `SMB0001` = `\_SB.PCI0.SMB1`**, `_STA` = 0x0F, `_CRS` decoded from DSDT
  (`artifacts/acpi/DSDT.aml`, device at file offset 0x111a8):
  - IO descriptor `47 01 20 0B 20 0B 20 20` → **base 0x0B20, length 0x20**
  - IRQ descriptor `23 80 00 18` → **IRQ 7**, level-triggered, active-low, shareable
  - No `_SBR`/`_SBW` control methods, so `i2c-scmi` cannot bind it; nothing in Linux claims it.
- **The pad ACKs at 0x2c on the 0xB20 bus** (`i2cdetect -y 11 0x2c 0x2c`), and *not* on buses 9/10.
  Bus **i2c-11 is piix4's existing aux adapter** at 0xB20 — plain `piix4_access`, no port mux, no IMC
  semaphore. Master reads/writes to the pad already work today.
- **ASF slave register recipe** is in mainline `drivers/i2c/busses/i2c-amd-asf-plat.c` (copy in
  `ref/`): register offsets base+0x07…0x15, FCH PM `DecodeEn` MMIO bits 16/17 (MSTR_EN/CLK_EN),
  IRQ handling, data-bank read sequence. That driver is **not** usable as-is here: it needs an
  `AMDI001A` ACPI node (absent) plus an EOI MEM resource, its adapter is write-only, and it never
  advertises `HOST_NOTIFY`. It serves as hardware documentation only.

### Approach

Patch **`i2c-piix4`** itself: add ASF Host Notify support to its existing aux adapter. This is the
same single-driver architecture `i2c-i801` uses on Intel, keeps one owner for the 0xB20 IO range,
and is the shape a future upstream RFC would take. Interrupt-driven, so no polling power cost.

## Deliverable

Out-of-tree module in `module/`:

- `i2c-piix4.c` — patched copy of the mainline source matching running kernel 7.1.8-arch1-3
  (pristine copy in `ref/i2c-piix4.c`)
- `i2c-piix4.h` — unchanged copy (needed for the out-of-tree build)
- `Makefile` — standard kbuild: `make -C /usr/lib/modules/$(uname -r)/build M=$PWD modules`
- `README.md` — what/why, build, load, revert
- `dkms.conf` — added only after the module is proven working

Prereq: `sudo pacman -S linux-headers` (7.1.8.arch1-3, matches running kernel).

## Patch design (all within i2c-piix4.c)

### 1. ASF detection (probe time)
`piix4_asf_detect(unsigned short aux_smba)`:
- Locate the ACPI device with HID `SMB0001` (`acpi_dev_get_first_match_dev("SMB0001", NULL, -1)`),
  walk `_CRS` via `acpi_dev_get_resources()` collecting IO base and IRQ.
- Enable ASF mode only when the ACPI IO base matches the aux adapter's `smba` (0x0B20 here);
  stash `piix4_asf_irq`.
- Module params: `asf_host_notify` (bool, default true — kill switch) and `asf_irq` (int, default
  -1 = take from ACPI).

### 2. Widen the aux IO region  ⚠️ easy to miss
`piix4_setup_sb800(..., aux=1)` currently does `request_region(piix4_smba, SMBIOSIZE /* 9 */)`,
covering only 0xB20–0xB28. **The ASF registers (base+0x09 ASFLISADDR, +0x0A ASFSTA, +0x0D ASFSLVSTA,
+0x11 ASFDATARWPTR, +0x12 ASFSETDATARDPTR, +0x13 ASFDATABNKSEL, +0x15 ASFSLVEN) fall outside it.**
When ASF is detected, request the full 0x20 bytes declared by `_CRS` instead, and release the
matching length in `piix4_adap_remove`. (`acpi_check_region` currently passes here because
`SMB0001` is not a `PNP0C02` motherboard-resource device.)

### 3. New algorithm for the aux adapter
```c
static u32 piix4_func_asf(struct i2c_adapter *a)
	{ return piix4_func(a) | I2C_FUNC_SMBUS_HOST_NOTIFY; }
static const struct i2c_algorithm piix4_smbus_algorithm_asf = {
	.smbus_xfer = piix4_access_asf, .functionality = piix4_func_asf };
```
Selected in `piix4_add_adapter()` for the aux adapter when ASF was detected. Functionality must be
correct **before** `i2c_add_adapter()`, since `i2c_setup_host_notify_irq_domain()`
(drivers/i2c/i2c-core-base.c:1472) creates the host-notify IRQ domain only if the adapter already
advertises `I2C_FUNC_SMBUS_HOST_NOTIFY`.

### 4. Master transfers: `piix4_access_asf`
Wrap the existing `piix4_access` with the listen-mode dance from `amd_asf_xfer`: reset slave and
drop listen (ASFSLVEN bit 4 / ASFLISADDR bit 0), clear ASFSLVSTA, set MSTR_EN (FCH PM MMIO bit 16
via the existing `piix4_sb800_region_request`/`piix4_sb800_region_release` helpers) → `piix4_access()`
→ restore slave state via `piix4_asf_setup_slave()` (recipe from `amd_asf_setup_target`: MSTR_EN off,
CLK_EN on, listen on, slave interrupt on). No port selection — the aux controller has none.

### 5. Slave reception → Host Notify
- After aux adapter registration: program the listen address to the SMBus Host address
  (`0x08 << 1 | I2C_M_RD`, per `amd_asf_reg_target`), run `piix4_asf_setup_slave()`, then
  `request_threaded_irq(irq, hard, thread, IRQF_SHARED, "piix4-asf", ...)`.
- Hard handler: read ASFSTA; if bit 6 (target interrupt) set, clear by writing it back and return
  `IRQ_WAKE_THREAD`; else `IRQ_NONE` (line is shared). No EOI MMIO write — that is a newer-platform
  concern in `i2c-amd-asf-plat`; here it is a legacy level IRQ through the IOAPIC.
- Thread: take the FCH PM region, read the data bank exactly as `amd_asf_process_target` does (bank
  select ASFDATABNKSEL, length ASFDATARWPTR, payload ASFINDEX), re-arm the bank, release. The first
  payload byte is the notifying device's address (`>> 1`) per the SMBus Host Notify wire format →
  `i2c_handle_smbus_host_notify(piix4_aux_adapter, addr)`. `dev_dbg` the raw payload for bring-up.

### 6. Teardown and suspend
- `piix4_remove`: free IRQ, disable slave interrupt and listen (per `amd_asf_unreg_target`).
- Known gap: ASF slave state across S3. If notify dies after resume, add a PM resume hook re-running
  `piix4_asf_setup_slave()`. Deferred until observed.

## Verification

Privileged steps run by the user via `!`. Nothing persists until the final step.

1. `make` in `module/`.
2. Swap in: `sudo modprobe -r psmouse; sudo rmmod rmi_smbus i2c_piix4; sudo insmod ./i2c-piix4.ko;
   sudo modprobe psmouse` — expect a new dmesg line naming the ASF IRQ; confirm i2c-11 still lists
   the pad (`i2cdetect -y 11 0x2c 0x2c`).
3. Attach: `sudo modprobe rmi_smbus; sudo sh -c 'modprobe -r psmouse && modprobe psmouse synaptics_intertouch=1'`
4. Success criteria:
   - dmesg shows `rmi4_smbus 11-002c` probing; `grep Name= /proc/bus/input/devices` reports
     `Synaptics TM3471-…` instead of `SynPS/2 Synaptics TouchPad`
   - IRQ 7 count in `/proc/interrupts` climbs while touching the pad
   - `libinput debug-events`: fast flicks produce multi-event `POINTER_SCROLL_FINGER` streams;
     two-finger report rate ≥100 Hz (vs ~40 Hz today)
   - TrackPoint still works; `evtest` shows MT slots ≥ 2
5. Revert at any point: `rmmod` ours → `modprobe i2c_piix4` → reload psmouse; or reboot.
6. On success only: install to `/usr/lib/modules/$(uname -r)/updates/`, `depmod`, persist
   `options psmouse synaptics_intertouch=1` in `/etc/modprobe.d/`, and package for kernel updates.
   **DKMS is the Omarchy-native mechanism** for a single out-of-tree module (they ship
   `yt6801-dkms`, `xpadneo-dkms`, `macbook12-spi-driver-dkms` the same way); this box runs stock
   Arch `linux` with neither `dkms` nor `linux-headers` installed yet. Omarchy-style refinement is a
   local PKGBUILD (`i2c-piix4-asf-dkms`) installed via pacman rather than raw `dkms add`. Since
   `i2c-piix4` is in-tree, verify after the first kernel update that the DKMS module in
   `updates/dkms` wins over the stock one.

## Risks (all recoverable)

- **IRQ 7 never fires** → pad stays PS/2, exactly the status quo. Diagnose via `/proc/interrupts`
  and direct ASFSTA reads. A storming shared IRQ is auto-masked by the kernel.
- **Aux SMBus wedges** → affects only the 0xB20 controller; the main SMBus (SPD, sensors) is a
  separate engine. Cleared by reboot.
- **Region conflict** if something else claims 0xB20–0xB3F → probe fails cleanly, module refuses to
  enable ASF, stock behaviour retained.

## Stretch

Submit as an RFC to linux-i2c + linux-input: *"i2c-piix4: support SMBus Host Notify via ASF on
SMB0001 platforms"*, plus adding `LEN2073` to `smbus_pnp_ids` in `drivers/input/mouse/synaptics.c`.
The Windows driver evidence (`SynAMDSmbDrv.inf` binding `ACPI\SMB0001`) plus a working implementation
makes a strong case, and it would fix every AMD ThinkPad of this generation.
