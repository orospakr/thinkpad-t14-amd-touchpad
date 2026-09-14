# Wake jump after a long suspend (2026-09-08)

## Symptom
After an overnight S3 (17:04 → 21:48, ~4.7 h) the cursor was "very slow to start
moving after putting a finger down"; TrackPoint unaffected. Both fixes were loaded
(rmi_smbus `resume_reconfig_after=1`, psmouse `synaptics_rmi_doze_interval=6`).

## Measurement (`doze/diag.sh`, `doze/touchlat.py`, `doze/firstdelta.py`)
Raw stream healthy: flat 15 ms clock, irq 95 == irq 99 == SYN_REPORTs, no stalls.
Regdump byte-identical to the working state (F01 ctrl 00 c8 00 06 2d 00).
But every single-finger drag started with a stale landing frame: frame 1 at the
landing point, frame 2 (15 ms later) already 5–11 mm away, then smooth ~2.5 mm/frame.

| capture | first-frame |delta| median | drags starting from rest |
|---|---|---|
| pressure-9 (2026-09-07, same config) | 0 | 13/13 |
| overnight-1 (before any action) | 71 units | 0/9 |
| overnight-2 | 74 units | 0/6 |
| overnight-4 (after hwreset + stack reload) | 0 | 7/7 |

Reading: the firmware went quiet between landing and first stream for tens of ms
(longer than the 60 ms doze interval would suggest — user-perceived delay was larger
than that), in a state register readback does not expose. libinput in Hyprland even
discarded one frame as a "touch jump".

## What it is not
- Hyprland's libinput had "hysteresis enabled" (wobble detector) — margin is
  resolution/4 = 3 units = 0.25 mm (fuzz 0), and it fired before the suspend. Irrelevant.
- Post-resume libinput decisions (palm/thumb/dwt) look normal in the Hyprland log.
- The config pass on resume (`rmi_reset()` after `rmi_driver_resume()`) ran and did not cure it.

## Cure attempt
1. `hwreset` sysfs (F01 device reset command, first use in this project) → **pad dead**:
   the SMBus mapping table is invalidated by a device reset, every read returns -6
   (ENXIO), `reconfig` cannot help. `rmi_smb_reset()` (clears the host-side mapping
   cache) is only called from probe and resume, never from the reset handler.
   **Do not use `hwreset` again without a transport re-init after it.**
2. `psmouse/load-exp.sh nosleep synaptics_rmi_nosleep=0 synaptics_rmi_doze_interval=6`
   revived the pad; drags start from rest (overnight-4); user: "delay is gone".

Not separable from this run: whether the F01 reset or the reload (PS/2 re-init of the
pad by synaptics_init + SMBus re-probe) was the cure.

## Cycle 2 (2026-09-09): 21.6 h S3 (23:47 → 21:25)
Reproduced ("delayed-start behaviour has returned"). `doze/seq.sh` (baseline → `xport_reset` →
rmi_smbus rebind → psmouse reload, drag capture after each) ran, but all four captures were empty:
the cues went unanswered and the script advanced anyway, ending in the reload. Harness lesson:
**never auto-advance a user-input step on an empty capture** — `doze/gcap.sh` now repeats a capture
(fresh cue each time) until ≥100 frames, and `doze/seq.sh` uses it; `doze/watch.sh LOG` is the
user-side cue watcher. Post-reload gated capture `long2-after`: 19 drags, first-frame median 0,
all ramp from rest → **a reload alone (no F01 device reset) cures it**. The F01 reset of cycle 1
was never needed.

Still unseparated: SMBus re-probe (`rmmod/insmod rmi_smbus` → `rmi_smb_reset` + PDT scan + config)
vs the PS/2 re-init psmouse does (`synaptics_init` → PS/2 reset + `synaptics_create_intertouch`).

## Cycle 3 (2026-09-10): 22.3 h S3 (23:34 → 21:51) — SEPARATED
`doze/seq.sh doze/long3`, all four captures answered:

| step | first-frame |delta| median | ramp from rest |
|---|---|---|
| baseline | 57 | 0/6 |
| `xport_reset` (rmi_reset = config pass) | 60 | 0/6 |
| rmi_smbus rmmod/insmod (rmi_smb_reset + PDT scan + all function probes + config) | 58 | 0/6 |
| psmouse reload (`load-exp.sh`) | 0 | 4/4 |

Nothing on the SMBus side reaches the state; the cure is on the **PS/2 side**. What the reload
sends the pad over PS/2 that resume does not: psmouse_probe (GETID, F6 set-defaults),
synaptics_detect (E6/E8 sequences), **psmouse_reset (FF, BAT)** in `synaptics_init_smbus()`,
synaptics_query_hardware (E8 queries), then `psmouse_smbus_init` → F5 deactivate. The resume path
for the SMBus companion (`psmouse_smbus_reconnect`) sends F5 only. Stock kernels do the same, so
stock SMBus-attached Synaptics pads plausibly show this too after long suspends.

Hypothesis: the pad drops into a deeper firmware sleep after hours without host traffic on either
bus (S3 = hours of silence on both); a PS/2 reset (or maybe any PS/2 command) brings it out.

## Cycle 4 (2026-09-11): 15.7 h S3 then 1.25 h S3, no cure between — ARMED
Delay present after both (user report; `arm1-base`: median 89 units, 0/5 from rest), so a short
S3 (with its resume config pass) does not clear the state either. `doze/arm.sh`: loaded the psmouse
build with `synaptics_rmi_ps2cmd` (`arm1-after`: median 0, 6/6). The trigger is live until reboot.

## Cycle 5 (2026-09-12): 2.5 h S3 (09:32 → 12:00) — PS/2 BISECT
Delay present after only 2.5 h (shortest yet; 90 s probe cycles never showed it).
`doze/ps2seq.sh doze/long4` with the `synaptics_rmi_ps2cmd` trigger:

| step | first-frame |delta| median | ramp from rest |
|---|---|---|
| baseline | 94 | 0/7 |
| F5 disable (= stock `psmouse_smbus_reconnect`) + rmi_smbus rebind | 115 | 0/7 |
| E8 query sequence (`synaptics_query_hardware`) + rebind | 0 | 8/8 |
| F6 set-defaults + rebind | 0 | 5/5 (already cured) |
| FF reset + F5 + rebind | 0 | 8/8 (already cured) |
| psmouse reload | 0 | 10/10 |

**Every PS/2 command, F5 included, kills the SMBus transport** (all reads -6 until rmi_smbus is
re-probed; `rmi_smb_reset()` clears the host mapping cache). Stock resume survives its own F5 only
because the i2c client (registered after psmouse) resumes after serio1, and `rmi_smb_resume()`
clears the mapping then. Any in-place PS/2 command on the companion must be followed by a
transport re-init — or be issued before the SMBus side resumes, as stock ordering already does.

**The E8 query sequence cures it; F5 does not.** Minimal command still open (F2 GETID? a single
E8 identify query?). Stock kernels send only F5 on resume → stock SMBus-attached Synaptics pads
plausibly show this delay after a few hours of suspend.

## Cycle 6 (2026-09-12): 2.3 h S3 (12:19 → 14:35) — MINIMAL COMMAND = F2 GETID
`STEPS="base getid e8 reload"`: baseline median 54 (0/8 from rest) → **F2 Get ID + rebind: 0
(7/7)** → E8, reload moot. One PS/2 identify command on resume is the fix; F5 alone is not.

Fix implemented in the experimental psmouse (`psmouse/nosleep/psmouse-smbus.c`,
`psmouse_smbus_reconnect()` sends GETID before the deactivate; param `psmouse_smbus_resume_getid`,
default 1) and drafted as `upstream/0003-...`. Loaded 2026-09-12 for an end-to-end test: the next
natural resume after ≥ 2 h should ramp from rest with no intervention (`doze/gcap.sh doze/e2e-1 doze/e2e-1.log`).

## Cycle 7 (2026-09-12 evening): 3.5 h S3 with the GETID-on-reconnect hook loaded — NOT CURED
Journal shows the hook ran (`smbus reconnect: GETID -> 0 (id 00)`) before `rmi_smb_resume`, SMBus
alive afterwards, delay still present (`long6-base`: median 64, 0/7). In place afterwards:
GETID + rebind → cured (9/9); then F5 + rebind → still cured (8/8), so the deactivate after GETID
is not what breaks it. `xport_reset` does NOT clear the SMBus mapping (reads stay -6), so this run
could not separate "resume-style mapping clear" from "full re-probe".

Why GETID at resume fails, candidates: (a) at resume the sensor is still in the F01 sleep mode set
by `rmi_f01_suspend`; every in-place cure hit an awake sensor. (b) the full rmi_smbus re-probe that
always followed GETID in place does part of the work.

**Harness gotchas found**: an rmi_smbus rmmod/insmod ("rebind") leaves the F01 IRQ-enable byte at
0x48 (F03 bit clear) and the TrackPoint dead until a psmouse reload — every rebind in cycles 5–7
did this. `clear_state` param added to the experimental rmi_smbus (mapping cache clear only, =
what resume does); sequences now use it instead of rebinding.

## Cycle 8 (2026-09-12 night): SHORT suspends do it too; the GETID hook is not the cause
- 4-min natural S3 with the hook on → delay (`long7-base`: median 62, 0/8).
- `seq7`: F01 hwreset + clear_state → SMBus still dead (a device reset needs more than a mapping
  clear; not a cheap SMBus-only fix) → reload cured (0, 9/9).
- **`doze/short.sh` controlled 240 s rtcwake with `psmouse_smbus_resume_getid=0` → delay
  (`short-off`: median 69, 0/7)**. The hook is not the cause. The "needs hours" idea was wrong:
  every S3 on this stack produces the jump; nobody had measured positions after a short cycle
  before (probe10 captures were SYN-only).
- hook-on half lost (user away; 8 unanswered cues).

So the wake jump follows every suspend with the current stack. Unknown whether stock does it,
or whether it is caused by what this stack adds at resume: the config-after-wake pass (0001,
`resume_reconfig_after=1`) and/or the doze_interval=6 pdata (0002, rewritten on every config pass).

## Control A (2026-09-13): stock resume order, hook off, 240 s rtcwake → NO JUMP, clock degraded
`doze/ctrl.sh doze/ctrlA 0 0`: first-frame median 0 (8/8 from rest); clock 12/13 ms with 23–24 ms
merged frames (the original resume jitter). **The config-after-wake pass (0001,
`resume_reconfig_after=1`) fixes the clock and causes the wake jump.** Both are the RMI config pass
hitting the firmware in a state it dislikes: before wake → 80 Hz clock; right after wake → stale
landing frames. The PS/2 GETID cure works because... (open; it clears the jump state but the config
pass on the awake sensor at rebind/reload did not re-create it — so either timing after wake
matters, or a specific write does).

## Cycle 9 (2026-09-13 night): ROOT CAUSE — a config pass on an already-configured pad
- `reconfig` 84 s after a stock-order resume (awake sensor): clock fixed AND jump (median 81).
- **PS/2 GETID resets the pad's RMI configuration to firmware defaults** (F01 IRQ enable 00 00,
  doze interval 3) — that is what "cures": the pad forgets the host config. Every PS/2 command
  does this, which is why they all killed the SMBus mapping (needs `rmi_smb_reset`, i.e. mapping
  clear + re-enable SMBus mode; the mapping clear alone is not enough).
- Write bisect (`doze/bisect.sh`, each write alone on a freshly reset pad): ctrl0 0, doze 0,
  F12 ctrl 0, others 0, control 0 → no single register.
- `doze/double.sh`: full pass on the reloaded (configured) pad → **100**; cure then first full
  pass → **0**; second full pass → **78**. ⇒ **the wake jump is produced by applying the config
  pass to a pad that already holds the host configuration.** A pass on a freshly reset pad is fine.
- `resume_reconfig_after=1` (loaded since 09-05) runs the pass twice at resume → jump after every
  S3. Control A (=0, stock order) → no jump but degraded clock. Patch 0001's move form (=2, one
  pass after wake) has never been measured — it is the candidate for both.
- Patch 0003 (GETID on resume) only "worked" by resetting the pad so the following pass was a
  first pass; with =1 there were still two passes → it failed at resume. Drop 0003.

## Control M2 (2026-09-13): move form (=2, one pass after wake), 240 s → clean clock, JUMP (111)
`f5probe`: **F5 resets the pad config exactly like GETID** (IRQ 00 00, doze 3), so every resume
starts from firmware defaults and one pass is needed. Stock order (pass, then `rmi_driver_resume`
= irq mask + F01 ctrl0) → no jump, bad clock. Move form (irq + ctrl0, then pass) → good clock,
jump. E2 (irq bits, then full pass) → no jump. ⇒ the jump needs the full pass *after the ctrl0
write*; which write in the pass? → `doze/bisect2.sh` (cure, ctrl0, then doze | F12 ctrl | others).

## Cycle 10 (2026-09-13, 22:00): the priming write is the F01 DOZE REGISTERS
On this pad a config pass writes only three things: F01 ctrl0, the three doze bytes (interval,
wakeup threshold, holdoff — all unconditionally), and the IRQ mask (F12/F54/F3A configs; the F12
control write is a no-op without dribble pdata).

`bisect2` (cure, ctrl0, then X): full 0 · doze 0 · F12 0 · others 0.
`bisect3` (cure, X, then full): others→full **6** · **doze→full 87** · **full→full 85**.
⇒ **writing the doze registers a second time since the last reset, on an awake sensor, produces
the wake jump**; a single write is clean in every order. (Probe writes interval once in
rmi_f01_probe and again in the probe config pass, but wakeup/holdoff only once → reload clean.)

The attention-driven reset handler ("Device reset detected") has never fired in 7 days of logs.
Move form (one pass after wake) still jumped, so at a real resume the pad most likely is NOT
reset by psmouse's F5 (it is in place — `f5probe`) and still holds the pre-suspend doze values;
stock order writes them while the sensor sleeps (no effect, degraded clock), after-wake writes
them on an awake sensor (jump). The `exp_doze_if_changed` log at resume will show which.

Fix candidate (experimental rmi_core `exp_doze_if_changed=1`): rmi_f01_config reads the three
doze regs and skips the writes when unchanged. Test: `doze/ctrl.sh doze/fixA 1 0` (double-pass
form, worst case) → expect clean clock and no jump.

## Cycle 11 (2026-09-13, 22:10): IT IS TIMING — config too soon after the PS/2 reset
- fixA (double-pass form + `exp_doze_if_changed=1`, 240 s): resume log shows the pad at firmware
  defaults (interval 3) → **psmouse's F5 does reset the pad at every resume**; doze written once,
  second pass skipped → still jump (91). Not a second write.
- `doze/early.sh` in place (GETID reset, rmi_smb_reset, full pass after DELAY):
  0 ms → 91 · 30 ms → 97 · 300 ms → 0 · 2 s → 0.
  ⇒ **a config pass issued within a few tens of ms of the pad's reset produces the wake jump**;
  the same pass ≥ 300 ms later is clean. The in-place "second write" pattern was an artifact of
  the cure always sleeping 2 s (first pass clean) — E1/E3/T2 jumped because... (see below).
  Control A (stock order, immediate) → degraded clock: the same early-config fault, different
  outcome. T10 (=1) cured the clock with the later second pass but the early first pass had
  already primed the jump.
- Open: why did a *second* pass ≥1 s after a clean first pass (E3/T2/T3) also jump? Possibly a
  doze rewrite on an awake sensor is itself a (mini) reset of the doze engine and the following
  writes in the same pass come "too soon" after it. Not needed for the fix.

**Fix candidate**: in `rmi_smb_resume()`, wait before the (single, stock-order) config pass:
`resume_reset_delay_ms` knob in the experimental rmi_smbus. Test: 240 s S3 with
`resume_reconfig_after=0 resume_reset_delay_ms=300` → expect clean clock AND no jump. That
replaces patch 0001 (and 0003).

## RESOLVED (2026-09-13, 22:22): settle delay after the PS/2 reset
- 100 ms → still jump (91). Threshold between 100 and 300 ms.
- **fixB: `resume_reconfig_after=0` (stock order, one pass) + `resume_reset_delay_ms=300`, 240 s S3
  → flat 15 ms clock AND first-frame median 0 (7/7).** Both resume symptoms gone with one change.
- Upstream patch 0001 rewritten: `msleep(300)` in `rmi_smb_resume()` before `rmi_reset()`
  (`upstream/0001-...settle...patch`); the reorder patch and the GETID patch are retired
  (`upstream/retired/`). 0002 (doze interval) unchanged.
- Loaders now set `resume_reconfig_after=0 resume_reset_delay_ms=300`.
- Still to do: more fixB cycles incl. an overnight one; narrow 100–300 ms if a reviewer asks.

## Open questions / next
- **`doze/ctrl.sh doze/ctrlM2 2 0`** (move form, no GETID, 240 s): expect clean clock and no jump.
- `doze/f5probe.log`: does F5 (stock resume) reset the config like GETID? Decides whether any
  pass is needed at resume (mode 3 = none, i2c/spi shape) or exactly one (move form).
- **In place now** (`doze/reconfig-now.sh doze/ctrlA2`): config pass minutes after resume on the
  awake sensor. Jump appears → the pass itself (bisect F01 doze regs vs F12 controls vs ctrl0).
  No jump + clock fixed → only a pass in the first ms after wake does it → delay the pass (or
  find the minimal write) in 0001.
- **Control A**: `doze/ctrl.sh doze/ctrlA 0 0` — config pass in stock order, no GETID, 240 s.
  No jump → 0001's after-wake config pass causes it (then: which write? F01 doze regs vs F12).
  Jump → stock order has it too (check the clock histogram: stock order may land in the 80 Hz state).
- **Control B** (if A jumps): psmouse `synaptics_rmi_doze_interval=0` (stock doze) + reload, then
  `doze/ctrl.sh doze/ctrlB 1 0`.
- **Control C**: stock stack (`psmouse/load.sh stock`, in-tree rmi_smbus) + 240 s + capture.
- **Next broken resume: `doze/seq7.sh doze/long7`** — F01 hwreset + clear_state + reconfig first
  (an SMBus-only fix candidate: if it cures, rmi_smb_resume could issue the F01 reset itself and
  none of the PS/2 side is needed), else GETID + clear_state (tests (b)), else reload.
- If GETID + clear_state cures in place but not at resume: (a) holds → the PS/2 poke must come
  after the sensor wake, i.e. from the SMBus side's resume (needs a psmouse↔rmi_smbus hook) or a
  deferred GETID + mapping clear.
- e2e: natural resume ≥ 2 h with 0003 loaded → `doze/gcap.sh` capture, expect median 0.
- Does the mechanism depend on idle time rather than S3? (awake-idle overnight test, still undone)
- Stock control: does the delay appear on the stock stack (no doze_interval, no 0001)? Expected yes.
- **Next suspend ≥ 3 h**: `STEPS="base getid e8 reload" doze/ps2seq.sh doze/long5` — F2 GETID
  alone first, E8 only if still broken.
- Upstream shape (after the minimal command is known): on resume, before the SMBus side comes
  back, have the Synaptics PS/2 side re-run its identify/query (as `synaptics_reconnect()` already
  does for PS/2-mode pads) instead of only deactivating. Ordering makes the mapping clear free.
- **Next long suspend**: PS/2 command bisect in place, gated captures after each: F5 alone (= stock
  resume) → E8 query sequence → F6 → FF reset (then check SMBus still alive; rmi_smbus rebind if not)
  → reload. Needs a trigger in the experimental psmouse (`synaptics_rmi_ps2cmd` param).
- **Next long suspend: run `doze/seq.sh doze/long3` + `doze/watch.sh doze/long3.log`** and answer
  the cues; the steps before the reload are the discriminators.
- Is it suspend length, or pad idle time? Test: leave the machine awake with the pad
  untouched for hours, then `doze/diag.sh` drags. Test: 90 s rtcwake, same capture
  (the 09-07 probe10 captures were SYN-only, no positions).
- Does stock (no doze_interval, no resume fix) show the same after a long suspend?
  The 08-28 era "worse after long suspend" reports may be this, not the clock.

## Files
`doze/diag.sh OUT [DUR]` regdump + irq deltas + filtered evtest; `doze/cure.sh TRIGGER OUT`
(pokes a sysfs trigger, checks pad, then diag); `doze/revive.sh OUT` (reconfig → test →
reload); `doze/gcap.sh OUT LOG` (gated capture), `doze/seq.sh PREFIX` (stepwise cure sequence),
`doze/watch.sh LOG` (cues); `doze/touchlat.py`, `doze/firstdelta.py`; captures `doze/overnight-{1,2,3,4}.*`, `doze/long2-{base,xport,smbrebind,reload}.*` (empty), `doze/long2-after.*`,
`doze/devinfo.txt` (evtest absinfo: X/Y res 12 units/mm, fuzz 0; libinput quirks).
