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

## Mechanism as understood (2026-09-05)

**Correction to the 2026-08-28 reading.** The cure trigger (`xport_reset` →
`rmi_reset()`) does *not* touch the SMBus transport. `rmi_reset()` is
`rmi_driver_reset_handler()` (rmi_driver.c:425): re-read the F01 IRQ mask,
run every function's `reset` hook (none exist), then run every function's
`config` hook — `rmi_driver_process_config_requests()`, i.e. the `reconfig`
trigger plus an IRQ-mask read. The transport reset (`rmi_smb_reset()`:
mapping-cache clear + `rmi_smb_enable_smbus_mode()`) is only reached from
`rmi_smb_resume()` itself and from probe (rmi_driver.c:803). So the "SMBus
activation half-sticks" story was wrong; what half-sticks is the **RMI
function config pass**, and what cures is running it again.

What the config pass writes (v7.1.9): F01 `ctrl0` (device control) plus doze
interval / wakeup threshold / doze holdoff if the pad advertises them; F12
control registers via `rmi_f12_write_control_regs()` (and IRQ bits); F03 just
re-enables its IRQ bit. F11/F1A/F21/F30/F3A/F54 are not present on this pad.

Stock `rmi_smb_resume()` order (rmi_smbus.c:379):

1. `rmi_smb_reset()` — transport cache clear + version read
2. `rmi_reset()` — **config pass, while the pad is still in the sensor-sleep
   mode `rmi_f01_suspend()` put it in.** `f01->device_control.ctrl0` still
   carries `RMI_SLEEP_MODE_SENSOR_SLEEP`, so F01 config re-writes *sleep*,
   then F12's control registers are written to a sleeping pad.
3. `rmi_driver_resume()` — enable IRQ, then `rmi_f01_resume()` writes
   `ctrl0` = normal mode. Nothing re-applies F12 afterwards.

`rmi_i2c_resume()` and `rmi_spi_resume()` call only `rmi_driver_resume()`; the
extra `rmi_reset()` is SMBus-specific (the PS/2 side reset the pad, so the
config must be re-applied) and it is ordered before the wake.

Hypothesis: applying the F12 (and/or F01 doze) configuration while the sensor
is asleep is applied inconsistently by the firmware — the pad wakes reporting,
but on its 80 Hz PS/2-mode scan clock — and re-applying it on an awake pad
fixes it. Consistent with `regdump` being byte-identical clean vs degraded
(same values, different firmware-internal state) and with the 50% rate (a
firmware race between the sleep→normal transition and the pending config).

Timing is **not** a factor. The config pass re-run at any point after wake
sticks:

| when the config pass is re-run | result |
|---|---|
| stock: before `rmi_driver_resume()` (pad asleep) | ~50% degraded |
| enable_smbus_mode only, after resume (T2) / at 2.2 s (T4) | 1/2, 1/3 — transport-only, no config pass: not a cure |
| 60 s after wake, untouched (T5) | **0/8** |
| 30 s (T6) | **0/6** (5 verified untouched) |
| 10 s (T7) | **0/5** |
| 3 s (T8) | **0/5** |
| 1 s (T9) | **0/5** |
| inside `rmi_smb_resume()`, right after `rmi_driver_resume()` (T10, `resume_reconfig_after=1`) | **0/8** (2026-09-05 ×2, 2026-09-07 ×6) + 1 clean natural resume |

Open: which write in the pass is the operative one (F01 ctrl0 re-write vs
F01 doze regs vs F12 control regs) — narrows the upstream patch and its
explanation, not the fix; and whether a pad-side readable says "config
half-applied" (nothing in regdump does).

## What cures a degraded pad (verified by capture, no suspend in between)

- **`rmi_reset()`** = IRQ-mask re-read + function config pass, via the
  `xport_reset` sysfs trigger in the experimental `rmi_core` — **5/5** on a
  degraded pad, and 0/29 degraded when issued 1–60 s after every wake. This
  is the minimal known cure. (`reconfig` = the config pass alone is the same
  thing minus the IRQ-mask read; never run on a degraded pad yet.)
- `rmi4_smbus` driver unbind + bind, no PS/2 traffic — 3/3 (does the config
  pass during probe, on an awake pad)
- full re-attach (`modprobe -r psmouse; rmmod rmi_smbus; modprobe rmi_smbus;
  modprobe psmouse synaptics_intertouch=1`) — yes (original finding)

Does not cure: rebinding the TrackPoint driver on the F03 pass-through;
`rmi_smb_enable_smbus_mode()` on its own after resume (T2, T4).

## Refuted

- **F6/F4 in `psmouse_cleanup()` at suspend** (the original plan's step 1):
  skipping them for SMBus companions — 5/8 degraded. Not the cause.
- `reset_delay_ms` 30 → 250 — 7/8.
- Config-register drift — regdump identical.
- TrackPoint / F03 ordering — t3: reconnecting the TrackPoint through F03
  neither degrades a clean pad nor cures a degraded one.
- ASF collisions — none logged during degraded captures.
- A post-resume timing window — the config pass re-run sticks at 1 s, 3 s,
  10 s, 30 s and 60 s alike (T5–T9, 29 cycles).

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
| T5 | 60 s untouched after wake, then activation, then capture | **0 / 8** (6 verified untouched; 2026-08-28 ×3, 2026-09-04 ×5) |
| T6 | same, 30 s (`probe9.sh N START 30`, log `probe9-w30.log`) | **0 / 6** (5 verified untouched; cycle 3 brushed, 29 IRQs) |
| T7 | same, 10 s (`probe9-w10.log`) | **0 / 5** (all verified untouched) |
| T8 | same, 3 s (`probe9-w3.log`) | **0 / 5** (all verified untouched) |
| T9 | same, 1 s (`probe9-w1.log`) | **0 / 5** (all verified untouched) |
| T10 | in-driver: `rmi_reset()` again after `rmi_driver_resume()` (`probe10.sh`, `probe10.log`) | **0 / 8** (+ natural resume after 6 unmeasured cycles: clean) |

Since 2026-08-28 the machine has gone through six unmeasured resumes on
stock behaviour (experimental `rmi_core`/`rmi_smbus` still loaded, all knobs
off; stock returns on reboot). Two long sleeps (22 h, 22 h) felt clean;
unmeasured, and two samples say nothing at 50%.

## Next steps (need a person at the console)

Each cycle: script suspends with a 90 s RTC alarm, you wake by lid or
keyboard (not by touching the pad), hands off for the wait, one swipe.
About 2 min per cycle.

1. ~~Finish T5~~ — done 2026-09-04, 8/8 clean (`rmi4/probe9.log`,
   cycles 4–8). `rmi4/cue.sh LOG` plays a sound + notification at each
   transition so the person at the console needs no stopwatch.
2. ~~Bisect the window~~ — done 2026-09-05: 30 s 0/6, 10 s 0/5, 3 s 0/5,
   1 s 0/5. No window.
3. ~~T10 — in-driver reorder~~ — done 2026-09-07: **0/8** (`probe10.log`),
   plus a clean capture after a natural resume with the knob on. Tested
   form: `rmi_reset()` *both* before and after `rmi_driver_resume()`. The
   cleaner upstream form (move it, one call) is untested — 8 cycles with
   `resume_reconfig_after=2` (skip the before-call) if wanted.
4. **Narrow the operative write** (optional, for the commit message): on a
   degraded pad run F01 config only / F12 config only (needs two more sysfs
   triggers in the experimental `rmi_core`); needs a stock-order loop that
   stops on the first degraded cycle (~2 cycles expected).
5. **Upstream patch** — drafted 2026-09-07:
   `upstream/0001-Input-synaptics-rmi4-configure-after-wake-on-SMBus-resume.patch`
   (move form: `rmi_reset()` after `rmi_driver_resume()`; applies to
   mainline 7.2-rc and v7.1.9). Before sending: (a) measure the move form
   itself — `rmi4/probe10.sh 8 1 2` (`resume_reconfig_after=2` skips the
   before-call), 8 cycles; (b) fill in the real name in From/Signed-off-by;
   (c) `checkpatch.pl`; (d) send to linux-input (Dmitry Torokhov, Benjamin
   Tissoires), independent of the i2c-piix4 RFC, mention the i2c/spi
   transports don't reconfigure on resume at all.
6. **Local stopgap** if the upstream path drags: the same one-hunk change to
   `rmi_smbus` via DKMS (replaces the in-tree module); no `rmi_core` change
   needed. Not done; nothing is installed for this thread.

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
the rest of that plan is dropped. The 2026-08-28 reading ("the SMBus-mode
activation half-sticks; the same activation issued late cures") mistook
`rmi_reset()` for the transport reset; corrected 2026-09-05 after the bisect
found no timing window. Original ruled-out list (ASF driver, sleep
duration, wake method, lock screen, fingerprint reader, PS/2-vs-SMBus resume
ordering, byte-identical SMBus resume traces clean vs degraded) still stands.

## Experimental knobs (all out-of-tree, nothing installed)

- `psmouse/patched`: no F6/F4 for companions; `psmouse/delay`:
  `synaptics_smbus_reset_delay=` (ms)
- `rmi4/patched/rmi_core.ko`: `resume_reconfig=` param; sysfs on
  `/sys/bus/i2c/devices/11-002c/rmi4-N/`: `regdump`, `xport_reset`,
  `reconfig`, `hwreset`
- `rmi4/smbus/rmi_smbus.ko`: `resume_reactivate=` (bool),
  `resume_reactivate_delay_ms=` (both transport-only, superseded),
  `resume_reconfig_after=` (1: `rmi_reset()` also after `rmi_driver_resume()`,
  2: after only = the upstream patch)
- loaders: `psmouse/load*.sh`, `rmi4/load-rmi.sh`, `rmi4/load-smbus.sh`;
  cycle drivers `rmi4/probe5.sh` (arm-by-arm), `probe6` (delay), `probe7`,
  `probe8` (delayed reactivation), `probe9` (`probe9.sh N [START] [WAIT_S]`:
  untouched WAIT_S then `xport_reset`; logs `probe9.log` / `probe9-wN.log`),
  `probe10` (`probe10.sh N [START] [MODE]`, in-driver `resume_reconfig_after=MODE`:
  1 = before+after, 2 = after only; logs `probe10.log` / `probe10-m2.log`);
  `cue.sh LOG` user-side sound/notify cues for a run

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
