# Post-suspend touchpad degradation — investigation and upstream plan

Status 2026-09-04. Separate from the ASF Host Notify driver (done, installed
via DKMS at bdacba0); this concerns the mainline `rmi_smbus` / `rmi_core`
resume path. **Priority: ahead of COLLISION-PLAN.md** — this hits ~50% of
resumes; collisions cost a handful of reports a week.

## Symptom

After roughly half of all S3 cycles the Synaptics TM3471 (LEN2073) comes back
reporting on a 12.5 ms (80 Hz, PS/2-rate) clock with ~1 in 4 frames merged
into 23–24 ms, plus occasional 170–620 ms stalls. Healthy is a flat 15 ms
(~67 Hz RMI4 clock; p90 = median, max ≈ 16 ms). Felt as subtle mushiness,
often not noticed at all — subjective feel is not a reliable detector; the
evtest `SYN_REPORT` histogram is. libinput is not involved.

The state is re-rolled by every suspend and does not persist: a degraded pad
comes back clean after the next clean roll (confirmed after a 22 h sleep).
Sleep length, wake method, lock screen, fingerprint reader, touching the pad
at wake, `rtcwake` vs `systemctl suspend`: none correlate.

## Mechanism as understood (2026-08-28)

`rmi_smb_resume()` runs the SMBus-mode activation twice before functions are
resumed: `rmi_smb_reset()` directly, then again via `rmi_reset()` →
`xport->ops->reset`. Activation = clear the host's mapping cache +
`rmi_smb_enable_smbus_mode()` (msleep(reset_delay_ms=30), then the SMBus
version read that "activates the touchpad").

When issued inside the resume window that activation **half-sticks**: the pad
answers on SMBus and reports touches, but scans on its 80 Hz PS/2-mode clock.
The *identical* activation issued later sticks fully:

| when the activation is issued | result |
|---|---|
| during resume (stock, twice) | ~50% degraded |
| 2.2 s after `suspend exit`, before first touch (T4, delayed work) | still degraded 1/3 |
| 60 s after wake, untouched (T5) | 0/3 degraded — too few samples |
| minutes later, by hand (`xport_reset` sysfs) | cured 5/5 |

Ordering relative to the F01 ctrl0 write (T2) and to TrackPoint/F03 traffic
(T3) does not matter. A longer pre-activation delay (T1, 30 → 250 ms) makes it
worse if anything (7/8). No config register differs between states
(`regdump`: F01 ctrl 0..15 + data0, F12 ctrl 0..63, F03 ctrl are
byte-identical clean vs degraded vs cured). F03 traffic is negligible while
degraded (3 vs 627 F12 IRQs). The ASF driver logs nothing during degraded
windows.

Open: the width of the window (somewhere between 3 s and 60 s), whether first
touch matters (T5 says probably not), and what the pad exposes that says
"activation stuck" so a fix can be self-detecting instead of a timer.

## What cures a degraded pad (verified by capture, no suspend in between)

- **`rmi_reset()` alone** (= `rmi_smb_reset()`: mapping-cache clear +
  `rmi_smb_enable_smbus_mode()`) — **5/5**, via the `xport_reset` sysfs
  trigger in the experimental `rmi_core`. This is the minimal cure.
- `rmi4_smbus` driver unbind + bind, no PS/2 traffic — 3/3
- full re-attach (`modprobe -r psmouse; rmmod rmi_smbus; modprobe rmi_smbus;
  modprobe psmouse synaptics_intertouch=1`) — yes (original finding)

Does not cure: rebinding the TrackPoint driver on the F03 pass-through.
`rmi_driver_process_config_requests()` was never reached as a cure (the
activation always came first).

## Refuted

- **F6/F4 in `psmouse_cleanup()` at suspend** (the original plan's step 1):
  skipping them for SMBus companions — 5/8 degraded. Not the cause.
- `reset_delay_ms` 30 → 250 — 7/8.
- Config-register drift — regdump identical.
- TrackPoint / F03 ordering — t3: reconnecting the TrackPoint through F03
  neither degrades a clean pad nor cures a degraded one.
- ASF collisions — none logged during degraded captures.

## Things that kill the pad outright (do not do these)

Tissoires' 2017 finding reproduced: **F4** (PS/2 enable) to the pad via the
i8042 → pad deaf on SMBus (-ENXIO). F5 afterwards does not revive it; only an
SMBus-side re-init does. Consequences for the harness:

- never `echo auto > /sys/bus/serio/devices/serio1/protocol` (races the
  deferred companion removal, lands on PS/2 fallback)
- never `drvctl reconnect` on serio1: it reconnects the subtree and the
  TrackPoint's full PS/2 re-init goes through the pad → deaf
- `psmouse/ps2cmd.py` can poke the aux port for experiments; F4 means a
  re-attach afterwards

Recovery from any of these: `psmouse/load.sh stock` (retries the -EEXIST
race). Check health with `grep Name= /proc/bus/input/devices | grep TM3471`.

## Results table

Test rig: `psmouse/`, `rmi4/` (READMEs there). Out-of-tree builds of
`psmouse`, `rmi_core`, `rmi_smbus` from v7.1.9 sources. Loops re-attach the
pad before every suspend so cycles are independent; one touch-triggered
capture per wake. Degraded = 12/13 ms mode with a 23–24 ms tail; clean =
14/15 ms only (`degraded()` awk: `/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2}
END{exit !(d>c)}`). Logs: `psmouse/ab/`, `rmi4/probe*.log`, `rmi4/t3.log`.

| # | change under test | degraded / cycles |
|---|---|---|
| stock reference | — | ~50% |
| 1 | `psmouse_cleanup()` skips F6/F4 for SMBus companions | 5 / 8 |
| T1 | `reset_delay_ms` 30 → 250 | 7 / 8 |
| T2 | `rmi_smb_enable_smbus_mode()` again after `rmi_driver_resume()` | 1 / 2 (stopped) |
| T4 | same, from delayed work 3 s after resume (fired at 2.2 s, before first touch) | 1 / 3 (stopped) |
| T5 | 60 s untouched after wake, then activation, then capture | 0 / 3 (2 verified untouched) — inconclusive |

Since 2026-08-28 the machine has gone through six unmeasured resumes on
stock behaviour (experimental `rmi_core`/`rmi_smbus` still loaded, all knobs
off; stock returns on reboot). Two long sleeps (22 h, 22 h) felt clean;
unmeasured, and two samples say nothing at 50%.

## Next steps (need a person at the console)

Each cycle: script suspends with a 90 s RTC alarm, you wake by lid or
keyboard (not by touching the pad), hands off for the wait, one swipe.
About 2 min per cycle.

1. **Finish T5** — 5 more untouched-60 s cycles (`rmi4/probe9.sh`). 8/8
   clean puts the fluke chance under 0.5%; any degraded cycle answers the
   question the other way and step 2 is moot.
2. **Bisect the window** — 5 cycles at 30 s, 5 at 10 s, via
   `resume_reactivate_delay_ms` on the experimental `rmi_smbus`
   (`rmi4/probe8.sh`). Total for 1+2: 10–15 cycles, 20–30 min.
3. **Find a pad-side signal.** ftrace `smbus` events around a late
   `xport_reset` on a degraded pad vs the same on a clean pad: does the
   version-read reply, a query register, or the first F12 packet differ?
   Also compare the first few F12 interrupt intervals after resume — the
   12.5 ms cadence itself may be the cheapest detector.
4. **Upstream shape**, in order of preference:
   1. self-detecting: re-run the activation when a post-resume check (from
      step 3) says it did not stick;
   2. re-run the activation on the first Host Notify after resume (the pad
      is demonstrably awake by then; needs to be shown to be outside the
      window);
   3. timer in `rmi_smb_resume()` — last resort, only with the bisect data
      to justify the number.
   Submit as its own series to linux-input (Dmitry Torokhov, Benjamin
   Tissoires) with the capture evidence; independent of the i2c-piix4 RFC.
5. **Local stopgap** if the upstream path drags: a systemd `system-sleep`
   post hook that writes `xport_reset` after a delay outside the window —
   requires the experimental `rmi_core` (or the patch) installed via DKMS.
   Not done; nothing is installed for this thread.

## Upstream context

- Tissoires 2017 series deliberately made resume a bare `F5`: a fully
  PS/2-initialised pad goes deaf on SMBus. "Force a full reconnect on resume"
  would be rejected on the merits (and is now known to be unnecessary).
  - https://lkml.kernel.org/lkml/20170110161128.7441-7-benjamin.tissoires@redhat.com/
  - https://lkml.rescloud.iu.edu/1609.3/01872.html
  - https://www.mail-archive.com/linux-kernel@vger.kernel.org/msg1240718.html (retry on resume)
- 2023: deactivate delay for T440p
  https://patches.linaro.org/project/linux-input/patch/20230726025256.81174-1-jefferymiller@google.com/
- https://www.spinics.net/lists/linux-input/msg78698.html
- New here: the pad comes back *alive* but on a different reporting clock;
  nobody has measured that, and the cure is the driver's own activation
  issued late.

## History

The 2026-08-27 plan assumed the cause was `psmouse_cleanup()` sending F5/F6/F4
to a device the SMBus stack owns, with the fix being to skip the reset for
SMBus companions and, failing that, re-applying the Synaptics PS/2 mode before
F5 (gated by PNP ID `LEN2073` or DMI). Step 1 was tested first and refuted;
the rest of that plan is dropped. Original ruled-out list (ASF driver, sleep
duration, wake method, lock screen, fingerprint reader, PS/2-vs-SMBus resume
ordering, byte-identical SMBus resume traces clean vs degraded) still stands.

## Experimental knobs (all out-of-tree, nothing installed)

- `psmouse/patched`: no F6/F4 for companions; `psmouse/delay`:
  `synaptics_smbus_reset_delay=` (ms)
- `rmi4/patched/rmi_core.ko`: `resume_reconfig=` param; sysfs on
  `/sys/bus/i2c/devices/11-002c/rmi4-N/`: `regdump`, `xport_reset`,
  `reconfig`, `hwreset`
- `rmi4/smbus/rmi_smbus.ko`: `resume_reactivate=` (bool),
  `resume_reactivate_delay_ms=`
- loaders: `psmouse/load*.sh`, `rmi4/load-rmi.sh`, `rmi4/load-smbus.sh`;
  cycle drivers `rmi4/probe5.sh` (arm-by-arm), `probe6` (delay), `probe7`,
  `probe8` (delayed reactivation), `probe9` (untouched-60 s)

## Harness gotchas

- Root commands go through the herdr pane; `herdr pane run` queues text
  behind a foreground job, so a "successful" command may not have run yet —
  check timestamps on result files.
- `motw*.sh` needs `timeout --foreground` or Ctrl-C cannot reach a blocked
  evtest (pad deaf) and the root pane wedges.
- Wake the laptop by keyboard or lid; waking by touching the pad
  contaminates the untouched-window cycles (probe9 cycle 1).

## Also pending (ASF driver, separate)

~100 hard IRQ-7 entries per Host Notify (level line held between hard-handler
ack and thread drain): mask `ASF_SLV_INTR` in the hard handler (thread already
re-enables it). One line; needs rebuild + DKMS reinstall.

## Artifacts

`resume-investigation/`: `motw.sh` (touch-triggered 20 s histogram), `m31.sh`,
`snap.sh` (ASF regs via /dev/port), `instr2.sh` (i8042.debug + dyndbg +
ftrace smbus across a suspend), `trace_L.txt`/`dmesg_L.txt` (clean),
`trace_L2.txt`/`dmesg_L2.txt` (degraded).
