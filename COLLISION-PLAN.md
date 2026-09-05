# ASF bus collisions vs. touch input integrity — debugging plan

Status 2026-09-04. Triggered by a field report (T14 Gen 2a, 20XLS08R00, BIOS
R1MET61W 1.31, kernel 7.1.9-arch1-2, i2c-piix4-asf-dkms @ bdacba0): 384
"Bus collision!" events over 5 days, 20–94/hr while active, ~0 idle, always
recovered by the ASF yield-retry. Reporter's hypothesis: a collision landing
mid-way through an F12 multi-finger read yields a *torn report* (fingers
sampled at different instants), which libinput classifies as a pinch — i.e.
the collisions are user-visible input corruption, not just log noise.

Separate from `RESUME-PLAN.md` (post-suspend 80 Hz jitter) and from the
pending hard-IRQ mask fix (efficiency only).

## What is already established

- The collision rate is *expected*: the pad is a second SMBus master; its
  Host Notify races host reads ~1–2×/min of active use. Our design yields
  (listen 1 ms, drain, retry ≤3×); measured ~1 retry/2 min active, 0 hard
  failures per 3-min run (`module/README.md` §3). 20–94/hr matches.
- `lost the bus (-11)` = arbitration loss; `no response (-6)` = the pad NAKs
  when about to notify. Both yield+retry.
- A *retry* is not a lost transfer. Lost = all 3 retries fail =
  `rmi4_f12 … Failed to read object data` in dmesg. That count is the one
  that matters.
- The "SMBus may be locked until next hard reset" text is stock
  `piix4_transaction` alarmism printed before our retry runs — misleading on
  this hardware.
- Structure (v7.1.9 sources): `rmi_f12_attention()` does ONE
  `rmi_read_block(f12->data_addr, pkt_size)`; `rmi_smb_read_block()` splits
  it into `SMB_MAX_COUNT`=32-byte SMBus block reads. F12 object data is
  ~8 B/finger plus leading data registers, so a multi-finger `pkt_size`
  plausibly spans ≥2 SMBus transactions → a collision + 1 ms yield between
  them stretches the intra-report window from ~µs to ~1–5 ms.
  (Also: the IRQ-status read in `rmi_process_interrupt_requests` precedes the
  data read — another seam.)

## Key unknowns

1. **pkt_size on TM3471** — does the F12 data read actually span >1 SMBus
   block read? (If it fits in 32 B, the mid-data tear can't happen and only
   the status/data seam remains.)
2. **Latched or live?** Does the pad latch the F12 data block per attention
   (tear impossible) or serve live registers (tear possible even without
   collisions; collisions widen the window)?
3. **Correlation** — do spurious pinches actually coincide with collisions?

## Plan

1. **Quantify the baseline (no code changes).**
   - `pkt_size`: dev_dbg or a one-liner in the experimental `rmi_core`
     (`rmi4/patched`) printing `sensor->pkt_size`, `f12->data1_offset`,
     `attn_size`; or infer from `regdump`-style query reads. Decide q1.
   - Enable dyndbg on the dkms module: `format "collision" +p`,
     `format "no response" +p`, `format "lost the bus" +p`; count
     retries/hr and confirm `Failed to read object data` stays ~0.

2. **Latch test (q2, no suspend, needs ~1 min of two-finger motion).**
   Add a sysfs trigger to the experimental `rmi_core` that, on the next F12
   attention, reads the data block TWICE back-to-back and logs both.
   While two fingers are moving:
   - identical pairs → latched per report (tear hypothesis dead at the data
     level; only the status/data seam remains);
   - differing pairs → live registers; compute how much a 1–5 ms resample
     moves a finger at normal scroll speed (expect several units).

3. **Correlation capture (q3, reporter can run this too).**
   - `libinput record /dev/input/eventX` (or `evemu-record`) alongside
     `journalctl -k -f -o short-precise | grep -E 'collision|lost the bus|no response'`.
   - User scrolls normally until a few spurious pinches occur; mark them
     (e.g. keyboard timestamp or just note the pinch in the libinput stream —
     GESTURE_PINCH events).
   - Analysis: for each pinch begin, distance to nearest collision line.
     Verdict: linked if pinches cluster within ~50 ms of collisions AND
     pinch rate ≈ 0 in collision-free intervals of similar use.

4. **Causal test — collision injection.** Raise the collision rate on demand:
   hammer i2c-11 with harmless master traffic (e.g. `i2cget -y 11 0x2c`
   loop, or better a tight SMBus read of the version register) while the
   user two-finger-scrolls. If pinch rate scales with induced collision
   rate → causal, proven without waiting days. (Reversible; worst case is
   log spam + retries.)

5. **If confirmed, fix directions (in preference order):**
   1. If data is live (q2): make the yield-retry restart the *entire* RMI
      block read after the drain, not just the failed 32-byte chunk — the
      whole packet is then sampled post-notify. Needs a hook: either
      rmi_smbus retries the full `rmi_smb_read_block` on -EAGAIN from the
      adapter, or the ASF driver exposes "a yield happened" so rmi_smbus can
      re-read. The former is clean and upstreamable on its own
      (rmi_smbus already owns the loop; the adapter already returns distinct
      errnos).
   2. Shrink the yield window (measure how long the drain actually takes;
      1 ms listen may be over-generous).
   3. If data is latched: nothing to fix for tears; pinches must have
      another cause (drop-length gaps? libinput thresholds) — measure gap
      length at pinch onset instead.
   4. Cosmetic regardless: on the ASF-managed adapter, downgrade/ratelimit
      the stock "Bus collision! SMBus may be locked…" dev_err for the cases
      the yield path retries (log once at info, dev_dbg thereafter).

6. **Reply to the reporter** (they offered to help): send the dyndbg
   formats, the step-3 correlation recipe, and ask for
   (a) `Failed to read object data` count over their 5-day window,
   (b) a libinput record around a few spurious pinches. Their data + ours
   feeds the upstream justification for 5.i.

## Constraints / rig notes

- Reuse `rmi4/patched` (`rmi_core` experimental attrs) and the loaders in
  `psmouse/`, `rmi4/` (`load-rmi.sh` etc.); everything out-of-tree, nothing
  persists across reboot.
- Steps 2–4 need someone at the console doing two-finger scrolls; no suspend
  cycles required (unlike RESUME-PLAN).
- Root work via the herdr pane `w3:p5`; `timeout --foreground` in any
  capture pipeline; never `drvctl reconnect` on serio1; never send F4 to the
  pad.
