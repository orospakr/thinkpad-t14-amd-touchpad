# Post-suspend touchpad degradation — investigation and upstream plan

Status 2026-08-27. Separate from the ASF Host Notify patch (which is done and
installed); this concerns the mainline `psmouse` / `rmi_smbus` resume path.

## Symptom

After some S3 cycles the Synaptics TM3471 (LEN2073) comes back on a 12.5 ms
(80 Hz) report clock with ~1 in 4 frames merged into 23–24 ms, plus 170–620 ms
stalls. Healthy is a flat 15 ms (p90 = median, max ≈ 16 ms). Felt as subtle
jitter. Raw `SYN_REPORT` spacing (evtest), so libinput is not involved.

Reproduction is **nondeterministic** (~50% of cycles): degraded after sleeps of
54 s, 60 s, 39 min, 18 h, 90 s; clean after 7, 10, 18, 23, 45 s and one 93 s.

## Ruled out by measurement

- The ASF driver: no collisions / NAKs / retries / wedge resets while degraded;
  the fix never touches `i2c_piix4`.
- Sleep duration, `rtcwake` vs `systemctl suspend`, lock screen, fingerprint
  reader (USB 06cb:00bd), touching the pad at wake.
- PS/2-vs-SMBus resume ordering: identical in clean and degraded runs
  (`F5` to the pad, then first SMBus read 120 ms later; enforced by the
  `device_link` in `psmouse-smbus.c`).
- The SMBus resume sequence: ftrace `smbus` events are byte-identical between
  clean (`trace_L`) and degraded (`trace_L2`) runs — same writes, same replies.

## Mechanism (software side)

- Suspend: `psmouse_cleanup()` (`psmouse-base.c`) sends the pad `F5` (disable),
  **`F6` (reset to bare PS/2 defaults)**, `F4` (enable stream) — to a device the
  SMBus stack owns.
- Resume: `psmouse_smbus_reconnect()` sends only `F5`; `rmi_smb_resume()` does
  `rmi_smb_reset()` (SMBus-mode re-enable) + `rmi_reset()` + function resume.
- The Synaptics PS/2 mode set at attach (`synaptics_set_mode`, before the
  InterTouch handoff) is never re-applied. After that, the pad's state is a
  coin flip — plausibly a race inside the pad between its PS/2 reset and the
  SMBus-mode re-enable.

Verified fix: full re-attach
`modprobe -r psmouse; rmmod rmi_smbus; modprobe rmi_smbus; modprobe psmouse synaptics_intertouch=1`.
Caveat: companion removal is deferred work; a re-attach racing it fails with
`-EEXIST` and lands on PS/2 fallback — check `ls /sys/bus/i2c/devices | grep 11-`
is empty, or just redo it. **Never** `echo auto > /sys/bus/serio/devices/serio1/protocol`
(same race, drops to PS/2 fallback).

## Upstream context

- Tissoires 2017 series deliberately made resume a bare `F5`: a fully
  PS/2-initialised pad goes deaf on SMBus. "Force a full reconnect on resume"
  would be rejected on the merits.
  - https://lkml.kernel.org/lkml/20170110161128.7441-7-benjamin.tissoires@redhat.com/
  - https://lkml.rescloud.iu.edu/1609.3/01872.html
  - https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg1240718.html (retry on resume)
- 2023: deactivate delay for T440p
  https://patches.linaro.org/project/linux-input/patch/20230726025256.81174-1-jefferymiller@google.com/
- https://www.spinics.net/lists/linux-input/msg78698.html
- New here: the pad comes back *alive* but in a different reporting mode; nobody
  has measured that.

## Plan

1. **Minimal generic fix candidate (test first).** In `psmouse_cleanup()`, for
   `PSMOUSE_SYNAPTICS_SMBUS` / `PSMOUSE_ELANTECH_SMBUS` skip `PSMOUSE_CMD_RESET_DIS`
   (`F6`) and `PSMOUSE_CMD_ENABLE` (`F4`) — or give the companion protocol its own
   `cleanup`. Argument: the SMBus-companion protocol must not reset a device it
   handed off. If A/B shows the degradation gone, no machine gating is needed.
   - Build: DKMS'd `psmouse` from the 7.1.9 source (same approach as the
     i2c-piix4 package: copy `drivers/input/mouse/`, out-of-tree kbuild).
   - Test: ≥10 `systemctl suspend` cycles each, stock vs patched, ≥60 s sleeps
     (RTC alarm: `rtcwake -m no -s 90; systemctl suspend`), touch-triggered
     20 s capture (`motw.sh`) after each. Degraded = 12/13 ms mode with a
     23–24 ms tail; clean = 14/15 ms only.
2. **If it must be conditional**, gating in order of upstream preference:
   1. Self-detecting: find a register (F01/F12 control, Synaptics mode) that
      differs between states; re-apply only then. Not found yet — the driver's
      own resume reads are identical; would need probing more of the pad.
   2. PNP-ID table in `synaptics.c` (pattern: `smbus_pnp_ids`,
      `forcepad_pnp_ids`, `topbuttonpad_pnp_ids`); `LEN2073` entry.
   3. DMI — last resort.
3. Fallback if (1) fails: re-apply the Synaptics mode on reconnect *before*
   `F5`, gated per (2).
4. Local stopgap (not upstream): systemd `system-sleep` post hook doing the
   re-attach ~2 s after resume.
5. Submit as its own series to linux-input (Dmitry Torokhov, Benjamin
   Tissoires), with the trace evidence; independent of the i2c-piix4 ASF RFC.


## Results 2026-08-27/28 (executing the plan)

Test rig: `psmouse/`, `rmi4/` — out-of-tree builds of `psmouse`, `rmi_core`,
`rmi_smbus` from the v7.1.9 sources (fetched from stable cgit; the local
mainline tree is 7.2-rc). Loops re-attach the pad before every suspend so
cycles are independent (the state is re-rolled by each suspend; it does not
persist). One touch-triggered capture per wake. Logs: `psmouse/ab/`,
`rmi4/probe*.log`, `rmi4/t3.log`.

| # | change under test | degraded / cycles |
|---|---|---|
| stock reference (earlier runs) | — | ~50% |
| 1 | `psmouse_cleanup()` skips F6/F4 for SMBus companions | 5 / 8 |
| T1 | `reset_delay_ms` 30 → 250 | 7 / 8 |
| T2 | `rmi_smb_enable_smbus_mode()` again after `rmi_driver_resume()` | 1 / 2 (stopped) |
| T4 | same, from delayed work 3 s after resume (fired 2.2 s after `suspend exit`, before first touch) | 1 / 3 (stopped) |
| T5 | 60 s untouched after wake, then activation, then capture | 0 / 3 (2 verified untouched) — inconclusive, stopped (user away) |

**Plan step 1 is refuted**: F6/F4 in `psmouse_cleanup()` is not the cause.

What cures a degraded pad (each verified by capture, no suspend in between):

- full re-attach (known) — yes
- `rmi4_smbus` driver unbind+bind, no PS/2 traffic — yes, 3/3
- **`rmi_reset()` alone = `rmi_smb_reset()` = mapping-cache clear +
  `rmi_smb_enable_smbus_mode()` (30 ms, then SMBus version read)** — yes,
  **5/5** (sysfs `xport_reset` trigger in the experimental `rmi_core`)
- `rmi_driver_process_config_requests()` — never reached (B always cured first)
- rebinding the TrackPoint driver on the F03 pass-through — no
- bare F5 via `drvctl reconnect` — invalid test: it reconnects the subtree, the
  TrackPoint re-init through the pad leaves the pad deaf on SMBus (-ENXIO)

What does *not* degrade a clean pad: TrackPoint `reconnect` through F03 (t3).

Things that kill the pad outright (Tissoires' finding reproduced): F4 (PS/2
enable) to the pad via the i8042 → SMBus deaf; F5 afterwards does not revive
it; only an SMBus-side re-init does. (`psmouse/ps2cmd.py` pokes the aux port
via /dev/port.)

Register state: `regdump` (F01 ctrl 0..15, F01 data0, F12 ctrl 0..63, F03
ctrl) is byte-identical clean vs degraded vs after-cure. Not a config value.
F03 interrupt rate is negligible in the degraded state (3 vs 627 F12 IRQs).

**Mechanism as now understood**: the resume path already runs the SMBus-mode
activation (twice: `rmi_smb_reset` then `rmi_reset`) before `rmi_driver_resume`,
and it only half-sticks — the pad works but scans on its 80 Hz PS/2-mode
clock. The *same* activation issued later sticks. 2.2 s after resume is
too early (T4), 60 s is fine (T5, few samples), minutes is always fine.
Ordering relative to the F01 ctrl0 write (T2) and to TrackPoint traffic (T3)
does not matter; a longer pre-activation delay (T1) does not help.
Open: the width of the window (bisect between 3 s and 60 s) and whether
"first touch" plays a role (T5 says probably not; needs ~5 more untouched
cycles at ~50% base rate to be sure).

Next when a person is at the console (each cycle needs one swipe; T5 cycles
also need 60 s hands-off after wake):
1. Finish T5 (≥5 more cycles). If clean: bisect the delay (10 s, 30 s) with
   `resume_reactivate_delay_ms` on the experimental `rmi_smbus`.
2. Then look for a pad-side signal that says "activation stuck" so the fix
   can be self-detecting rather than a timer — e.g. compare the SMBus version
   read reply / mapping-table behaviour / a query register right after resume
   vs after a successful late activation (ftrace `smbus` events around
   `xport_reset`).
3. Upstream shape if it must be a timer: delayed re-activation in
   `rmi_smb_resume()` is ugly; better is re-activating on the first Host
   Notify after resume, or an F01-status-driven check — needs (2).

Experimental knobs (all out-of-tree, nothing installed):
- `psmouse/patched`: no F6/F4 for companions; `psmouse/delay`:
  `synaptics_smbus_reset_delay=` (ms)
- `rmi4/patched/rmi_core.ko`: `resume_reconfig=` param; sysfs on
  `/sys/bus/i2c/devices/11-002c/rmi4-N/`: `regdump`, `xport_reset`,
  `reconfig`, `hwreset`
- `rmi4/smbus/rmi_smbus.ko`: `resume_reactivate=` (bool),
  `resume_reactivate_delay_ms=`
- loaders: `psmouse/load*.sh`, `rmi4/load-rmi.sh`, `rmi4/load-smbus.sh`;
  cycle drivers `rmi4/probe5.sh` (arm-by-arm), `probe6` (delay), `probe7`,
  `probe8` (delayed reactivation), `probe9` (untouched-60s)
- gotcha: `motw*.sh` needs `timeout --foreground` or Ctrl-C can't reach a
  blocked evtest (pad deaf) and the root pane wedges; `herdr pane run` queues
  text behind a foreground job.

## Also pending (ASF driver, separate)

~100 hard IRQ-7 entries per Host Notify (level line held between hard-handler
ack and thread drain): mask `ASF_SLV_INTR` in the hard handler (thread already
re-enables it). One line; needs rebuild + DKMS reinstall.

## Artifacts

Copied into `resume-investigation/`: `motw.sh` (touch-triggered 20 s histogram),
`m31.sh`, `snap.sh` (ASF regs via /dev/port), `instr2.sh` (i8042.debug + dyndbg +
ftrace smbus across a suspend), `trace_L.txt`/`dmesg_L.txt` (clean),
`trace_L2.txt`/`dmesg_L2.txt` (degraded).
