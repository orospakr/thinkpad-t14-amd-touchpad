# Gesture reliability: dropped taps and phantom pinches — RESOLVED to F01 doze (2026-09-07)

Status 2026-09-07. Opened 2026-09-04 as "ASF bus collisions tear multi-finger
F12 reads → spurious libinput pinch" (field report + our own pinch/right-click
mis-triggers and unreliable tap-to-click). **The collision hypothesis is
superseded.** Root cause, measured: the pad is allowed to **doze** (F01 ctrl0
NoSleep bit clear, firmware default) and in RMI4/SMBus mode its doze behaviour
drops short touches and garbles the first frame of a two-finger landing.
Setting NoSleep fixes both symptoms outright. The ASF collisions are what
`module/README.md` always said they were: expected, retried, cosmetic.

## Evidence (all in `collision/`, captures `pressure-N.{evtest,libinput}`, scripts below)

Pipeline check — every capture counted Host Notify IRQs (`rmi4_smbus`, irq 95),
F12 function IRQs (irq 99) and evtest frames. They agree to within a few
(e.g. 424 / 422 / 421). Nothing is lost between pad and userspace; whatever
the pad reports arrives, and whatever is missing was never reported.

| capture | knobs | task | result |
|---|---|---|---|
| 2 | stock | ~20 taps (10 normal, 10 light) | 5 touches reached the kernel |
| 3 | stock | 15 quick + 15 slow (¼ s) taps, counted | 10 touches; slow taps missed as often as quick |
| 4 | stock | 20 quick taps, counted | **6 touches**, each a single ~15 ms frame; 424 notifies = 422 frames |
| 5 | stock | 10 two-finger scrolls | **1 pinch**; libinput scale 2.45 on the first update |
| 6 | NoSleep + kernel_tracking | 20 quick taps | **20 touches, 19 clicks**, taps now 90–170 ms / 3–7 frames |
| 7 | NoSleep + kernel_tracking | scrolls (85 episodes) | **0 pinches** |
| 8 | NoSleep only | scrolls (147 episodes) | **0 pinches** — kernel tracking not needed |
| 9 | **doze_interval=6, sleep allowed (= Windows)** | 20 quick taps | **20 touches**, 60–190 ms / 4–10 frames, 17 clicks (3 ran past the 180 ms tap limit) |
| 10 | doze_interval=6 | scrolls (145 episodes) | **0 pinches** |

The capture-5 pinch, frame by frame (`collision/frames.py`): landing frame
reports A=(719,493) B=(635,635); next frame A=(658,568) B=(702,503) — both
"moved" ~100 units in opposite directions. Swap the labels in the landing
frame and both move 20–70 units in the scroll direction. The firmware's
object order on the doze-wake landing frame is wrong; libinput sees the
separation collapse 165→78 and calls it a pinch. With NoSleep the landing
frames are sane (the only "jumps" left are a finger leaving the top edge).

Register state: F01 ctrl0 reads 0x00 stock, 0x04 with NoSleep (the write
sticks; the Configured bit 0x80 never reads back on this pad). This pad has
two IRQ-enable bytes (ctrl1..2 = c8 00), so the doze registers are ctrl3..5:
stock **doze interval 3, wakeup threshold 0x2d (45), doze holdoff 0** — the
pad dozes the instant a finger lifts, which is why taps 1 s apart were lost.
(An earlier reading had these shifted by one byte.) Windows (Lenovo SynPD.inf,
`AdjustFWDozeInterval_AddReg`, applied to group 25 = `ACPI\LEN2073` and 11
other IDs: LEN040D–0411, 0417, 0418, 2064, 2149, 2161, 2162) sets
`RMIDozeInterval = 6` and leaves NoSleep alone; tested as capture 9/10. libinput quirks
for the device: only `AttrThumbPressureThreshold=100` (Lenovo/"*Synaptics*"
match); fingertips report pressure 50–70, not a factor. One firmware
palm-flagged touch (tool type 2, pressure 82, major 10) seen in capture 1
— libinput ignores such touches; rare, not the main effect.

Refuted along the way: libinput thumb/pressure thresholds; host-side loss
(collisions, torn reads — counters and frames say no); report-clock state
(all of this happened on a pad verified clean by capture); scan-rate /
debounce (¼ s touches were dropped too).

## Why doze does this (working model)

With NoSleep clear the sensor drops to its doze scan as soon as the last
finger lifts (holdoff 0) and in doze it samples
for finger presence at a much lower rate. A tap that lands between doze
samples is never seen; one that is seen gets one frame before the finger is
gone; a two-finger landing that wakes the sensor gets a first frame built
before object tracking has settled. In PS/2 mode the same pad did not show
this (the PS/2 firmware path presumably manages doze differently), which is
why it is new since the RMI4/InterTouch switch.

## Fix directions

1. **Working now (out-of-tree)**: `psmouse/nosleep/psmouse.ko` with pdata
   power-management module params (`psmouse/psmouse-rmi-pdata-knobs.diff`).
   Loaded 2026-09-07 22:21 as `psmouse/load-exp.sh nosleep
   synaptics_rmi_nosleep=0 synaptics_rmi_doze_interval=6` — the Windows
   configuration. Nothing installed; stock returns on reboot. NoSleep
   (`synaptics_rmi_nosleep=1`) works equally but forbids doze altogether.
2. **Upstream shape — decided 2026-09-07**: `doze_interval = 6`, the value
   Lenovo's Windows driver programs for this pad, keeps the doze power
   saving and fixes both symptoms (captures 9/10). Patch: in
   `drivers/input/mouse/synaptics.c`, set
   `pdata.power_management.doze_interval = 6` for pads matching the
   Windows list (LEN040D LEN040E LEN040F LEN0410 LEN0411 LEN0417 LEN0418
   LEN2064 LEN2073 LEN2149 LEN2161 LEN2162), keyed by PNP ID like
   `smbus_pnp_ids`. rmi_f01 already writes a non-zero pdata doze interval
   at probe and on every config pass. Why the stock interval of 3 loses
   touches while 6 does not is a firmware question (the register may not be
   a plain period); the measurement is what matters for the patch.
3. Field reporter: their pinches are almost certainly this, not collisions.
   Reply with the finding and the `synaptics_rmi_nosleep` test build once
   the upstream shape is chosen.
4. Cosmetic, unchanged: ratelimit the stock "Bus collision! SMBus may be
   locked…" line on the ASF-managed adapter; ASF hard-IRQ mask one-liner.

## Rig

- `collision/pressure-capture.sh OUT` (`DUR=` seconds): evtest MT stream +
  `libinput debug-events --verbose --enable-tap` + irq counter deltas, with
  a pressure histogram / tool types / gesture summary.
- `collision/touches.py LOG.evtest`: per-touch table (begin, duration, tool,
  max pressure, max major, frames). `collision/frames.py LOG.evtest`:
  two-finger frames with separation-jump flags (needs ABS_MT_SLOT in the
  log — captures 1–3 predate that and merge slots).
- Root work via the herdr pane `w3:p5`; user-side cues with
  `notify-send` + `pw-play`; `timeout --foreground` in every pipeline.

## Original collision material (kept for the record)

Field report: 384 "Bus collision!" over 5 days, 20–94/hr active, ~0 idle,
always recovered. Established: the rate is expected (pad is a second SMBus
master), a retry is not a loss, `Failed to read object data` is the count
that matters (9 in the week before 2026-09-04, 0 during any capture), and
the stock "SMBus may be locked until next hard reset" text is alarmism. The
latch test / correlation / collision-injection steps were never needed: the
counters show no host-side loss during the captures that reproduced the
symptoms, and the symptoms went away with a pad-side register bit.
