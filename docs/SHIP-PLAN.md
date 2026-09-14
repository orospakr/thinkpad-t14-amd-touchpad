# SHIP-PLAN: public DKMS repo, Omarchy carry, upstream track

2026-09-13. Turns the research tree into a public repo users can install with
DKMS, packaged for omarchy-pkgs, wired into Omarchy with a detector, following
the tier-2 shape from "Carry, Don't Fork" (patches applied at DKMS build time,
never copied `.c` files; narrow detector; upstream status on every carry; a
sunset that the install script enforces).

## What was checked

- `dkms.conf` supports several modules in one package (`BUILT_MODULE_NAME[n]`,
  `BUILT_MODULE_LOCATION[n]`), applies `PATCH[n]` from a `patches/` subdirectory
  with `patch -p1` from the source root, and offers `PRE_BUILD` and
  `BUILD_EXCLUSIVE_KERNEL` (exit 77, which autoinstall skips silently).
- Arch's 7.1.9 kernel patch has five hunks, none under `drivers/input` or
  `drivers/i2c`: the pristine copies in `rmi4/src` and `psmouse/src` are what
  Arch ships. Plain-file fetches from `git.kernel.org` at a tag work (HTTP 200).
- Arch's `linux` PKGBUILD on main is already 7.2.4; this machine's Omarchy
  stable channel is on 7.1.9. The 7.2 refresh is the first job for CI.
- The UKI initramfs (autodetect + keyboard hooks) holds `rmi_core` and the
  modprobe conf but none of `i2c-piix4`, `rmi_smbus`, `psmouse`. The three
  overrides load from the root filesystem, where `/updates` wins. No UKI rebuild
  is needed when the package changes.
- DKMS archives the stock module as `original_module` on first install and
  restores it on remove (already the case for `i2c-piix4` here).
- `rmi_smbus` autoloads from the `i2c:rmi4_smbus` alias when psmouse creates
  the client; the `softdep` line in the modprobe conf is bring-up insurance.
- omarchy-pkgs `.omarchy/package.json` understands
  `"source": "local", "upstream": { "github": "owner/repo", ... }` and
  `"git_tags"` with `sources: archive/{tag}.tar.gz`, so a package can track
  tags of a personal GitHub repo and `check-versions` bumps it. Unknown keys
  such as the proposed `hardware` block are not rejected.
- Omarchy detectors are shell one-liners in `bin/omarchy-hw-*` built on
  `omarchy-hw-match` (DMI product name/family, case-insensitive). Hardware
  scripts in `install/hardware/` call `omarchy-pkg-add`. The existing
  `fix-synaptic-touchpad.sh` only modprobes in the installer chroot and never
  affects an installed machine.
- Identifiers on gondolin: DMI family `ThinkPad T14 Gen 2a` (Intel siblings are
  `Gen 2i`), PCI `1022:790b`, ACPI `SMB0001:00`, serio firmware `LEN2073`.

## Decision: one DKMS package, three modules

One package. Reasons:

- The three modules are one user-facing fix on one hardware family; the input
  patches are inert without the ASF one. One detector, one `omarchy-pkg-add`.
- The Carry Census names DKMS breakage as the most common failure class above
  tier 0. Three packages triple the surface for the same benefit.
- Kernel-series drift hits all three pristine copies at once, so the
  maintenance event is one anyway.
- Sunsets stay per module: when a patch lands in Arch's kernel, the next
  release drops that module from `dkms.conf` and its sources. Upstream status is
  tracked per patch in the README.

Splitting into three would not shrink the psmouse override (the whole PS/2
mouse stack for a twelve-line change); it would only add packaging.

## Repo layout

The DKMS source root is a kernel-tree subset, so the upstream-format patches
apply verbatim with `patch -p1`:

```
README.md, LICENSE (GPL-2.0-only)
dkms.conf
Makefile                              # obj-m += drivers/i2c/busses/ drivers/input/rmi4/ drivers/input/mouse/
KERNEL_SOURCE                         # v7.1.9 (tag the pristine copies came from)
patches/
  0001-i2c-piix4-add-ASF-SMBus-Host-Notify-on-SMB0001-platforms.patch   [FOR-UPSTREAM]
  0002-Input-synaptics-rmi4-let-the-device-settle-after-the-PS2-reset-on-SMBus-resume.patch   [FOR-UPSTREAM]
  0003-Input-synaptics-set-the-RMI4-doze-interval-Lenovo-uses-on-affected-pads.patch          [FOR-UPSTREAM]
  0004-Input-synaptics-enable-InterTouch-on-LEN2073.patch                                    [FOR-UPSTREAM]
drivers/i2c/busses/{i2c-piix4.c,i2c-piix4.h,Makefile}
drivers/input/rmi4/{rmi_smbus.c,rmi_bus.h,rmi_driver.h,Makefile}
drivers/input/mouse/{*.c,*.h,Makefile}   # Makefile keeps the in-tree psmouse-$(CONFIG_...) form
tools/refresh-sources.sh <tag>          # per-file fetch from git.kernel.org stable, updates KERNEL_SOURCE
tools/check                             # installed as <pkg>-check: dkms status, modinfo -n -> /updates, pad in RMI mode
packaging/arch/{PKGBUILD,<pkg>.install,<pkg>.conf}
packaging/omarchy/{install-hardware.sh,omarchy-hw-<detector>}   # the two files for the omarchy PR
research/                               # everything that is not the module
```

`research/` takes `collision/`, `doze/`, the `psmouse/` and `rmi4/` rigs,
`resume-investigation/`, `artifacts/`, `PLAN.md`, `RESUME-PLAN.md`,
`COLLISION-PLAN.md`, `dmesg.out`, `test-cycle.sh`, `upstream/retired/`. Moves
by `git mv` so history follows. `ref/` goes away: the pristine copies under
`drivers/` are the reference. `module/` and `pkg/` are replaced by the patch
plus `packaging/`. `upstream/` becomes `patches/`: the DKMS patch set and the
mailing-list series are the same files.

`drivers/input/mouse/` carries the whole directory because psmouse is one
module built from all of them; the Makefile mirrors the in-tree
`psmouse-$(CONFIG_MOUSE_PS2_*)` lines so it follows the kernel config instead of
a hard-coded object list.

## Patches

- 0001 ASF: generate with a real commit message from `ref/i2c-piix4.c` to
  `module/i2c-piix4.c`. One patch for DKMS; the mailing-list version gets
  split into a series later and the DKMS copy follows it.
- 0002, 0003: as in `upstream/` today, with real `From:` and `Signed-off-by:`.
- 0004: add `LEN2073` to `smbus_pnp_ids` in `synaptics.c`. Retires the
  `options psmouse synaptics_intertouch=1` line, which forced the SMBus
  transport on every Synaptics pad on the machine (the concern Omarchy's own
  `fix-synaptic-touchpad.sh` comment raises). The modprobe conf keeps only the
  `softdep`, or nothing if the alias autoload proves enough.
- Subject prefixes per OGC: `[FOR-UPSTREAM]` now, `[FROM-ML]` plus lore link
  once posted, dropped when merged.

## Kernel-series policy

Pristine copies are pinned to a kernel series (`KERNEL_SOURCE`). `PRE_BUILD`
compares `kernelver` major.minor against it and fails loudly on mismatch; a
loud DKMS failure in pacman output beats the exit-77 silent skip, and the
`-check` command turns a stock-module fallback into a visible state.

CI (GitHub Actions, `archlinux` container) runs on push and on a schedule:
for each Omarchy channel's `linux` version, refresh sources into a temp tree,
apply the four patches, build against that kernel's headers. A new series
fails CI before it reaches users; the fix is `tools/refresh-sources.sh`, a
patch re-check, and a tagged release. Arch main is at 7.2.4 already, so the
first CI run does the 7.2 refresh.

## Packaging

- PKGBUILD in the repo, sourced from the tagged GitHub tarball;
  `depends=('dkms' 'linux-headers')`; `conflicts`/`replaces`
  `i2c-piix4-asf-dkms` so gondolin migrates. Files land in
  `/usr/src/<pkg>-<ver>/` and Arch's dkms alpm hooks build and install them.
- `.install`: post-install and post-upgrade print "reboot, or run
  `<pkg>-check` after reloading"; no UKI rebuild (verified above). If a later
  version adds a modprobe option that matters at early boot, copy the
  sidecar-amps rebuild block then.
- omarchy-pkgs entry: `pkgbuilds/<pkg>/PKGBUILD` plus
  `.omarchy/package.json` with `"source": "local"` and an `upstream.github`
  block pointing at the repo's releases, so `check-versions` picks up tags.
  Include the proposed `hardware` block (detect, tier 2, upstream status per
  patch, owner) even though nothing enforces it yet.

## Omarchy wiring

- Detector `bin/omarchy-hw-thinkpad-t14-gen2-amd`:
  `omarchy-hw-match "T14 Gen 2a"` and `SMB0001:00` present under
  `/sys/bus/acpi/devices` and `LEN2073` in a serio `firmware_id`.
- `install/hardware/lenovo/fix-t14-gen2-amd-touchpad.sh`:
  `if omarchy-hw-thinkpad-t14-gen2-amd; then omarchy-pkg-add linux-headers <pkg>; fi`,
  with a kernel-version sunset guard once `fixed_in` is known. Added to
  `hardware/all.sh` next to the Yoga entry.
- Per the census: open an issue with findings first, not a draft PR.

## Open decisions

1. Name. The scope is "AMD FCH SMB0001 platforms with a Synaptics RMI4 pad",
   which today means this ThinkPad. Candidates: `thinkpad-t14-amd-touchpad`
   (matches Omarchy's machine-named packages) or `amd-asf-synaptics-touchpad`
   (matches the hardware scope). Package gets a `-dkms` suffix either way.
2. Whether to keep the `softdep` line or rely on the alias autoload.
3. Kernel guard strictness: fail loudly on a different series (recommended) or
   allow any kernel where the patches apply and the build succeeds.

## Sequence

1. Patches: generate 0001 from ref/module, write 0004, real author fields on
   all four, checkpatch, `git format-patch` clean against mainline.
2. Layout: `git mv` research into `research/`, create the kernel-subset tree,
   Makefiles, `dkms.conf`, `PRE_BUILD`, `tools/refresh-sources.sh`.
   `dkms build` from the working tree, load the three modules, confirm pad and
   TrackPoint, suspend and resume. This is the first time modules built from the
   final patches run.
3. Packaging: PKGBUILD, `.install`, `-check`; `makepkg`; install over
   `i2c-piix4-asf-dkms`; reboot; `-check`; overnight suspend soak.
4. CI and the 7.2 refresh.
5. README (which machines, install, check, remove, upstream status table,
   sunset conditions), LICENSE, first tag.
6. omarchy-pkgs issue then PR; omarchy issue then PR (detector + script).
7. Mailing-list track in parallel: linux-i2c for 0001, linux-input for
   0002 to 0004. Update prefixes and `upstream.ref` as each is posted.
   Details, maintainers, precedents and per-patch checklists are in
   `upstream/UPSTREAMING-NOTES.md` (2026-09-14). Changes it forces:
   - 0001 goes out as an RFC that opens with the 2024 history (Shyam Sundar's
     ASF series started in i2c-piix4 and was moved to a platform driver on
     Andy Shevchenko's review) and the reason that cannot apply here:
     `acpi_platform.c` refuses a platform device for SMB0001 when it has
     `_CRS`, which ours does. Rename slave -> target first. Cc Shyam Sundar
     S K, Mario Limonciello, Andy Shevchenko; Andi Shyti is the maintainer,
     not Wolfram Sang. Credit Miroslav Bendík's 2022 out-of-tree attempt.
   - Frame both series with 2fd003ee8ade (Lenovo removed InterTouch from
     T14/P14s Gen 1 AMD because Host Notify was unavailable). Patch 4 goes
     last, should probably restore LEN2064 as well, and must cite the
     public negative result (LEN2073 alone did nothing on 7.0-rc3).
   - Before posting 0002, settle the reset_delay_ms question: RESUME-PLAN
     T1 (reset_delay_ms 30 -> 250, inside rmi_smb_enable_smbus_mode, before
     the SMBus-mode re-enable) was 7/8 degraded, while 300 ms after
     rmi_smb_reset and before the config pass was 7/7 clean. Measure 250 ms
     at our position and 300 ms via reset_delay_ms to learn whether it is
     the extra 50 ms or the position. Dmitry will ask.
   - Reply to William Luther Zambo's unanswered L14 Gen 1 AMD thread
     (2026-09-01) rather than opening a new one; he is a Tested-by
     candidate for 0001 and 0003.
