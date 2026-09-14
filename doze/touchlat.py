#!/usr/bin/env python3
"""Per-touch timing from a filtered evtest log: frame intervals at touch start, stalls."""
import sys, re, collections
frames = []   # (t, {slot: tracking_id}, events)
cur = {}; t = None; slot = 0; ids = {}
for line in open(sys.argv[1], errors='replace'):
    m = re.match(r'Event: time (\d+\.\d+), (.*)', line)
    if not m: continue
    t = float(m.group(1)); rest = m.group(2)
    if 'SYN_REPORT' in rest:
        frames.append((t, dict(ids), dict(cur))); cur = {}
        continue
    m2 = re.search(r'\((\w+)\), value (-?\d+)', rest)
    if not m2: continue
    code, val = m2.group(1), int(m2.group(2))
    if code == 'ABS_MT_SLOT': slot = val
    elif code == 'ABS_MT_TRACKING_ID':
        if val < 0: ids.pop(slot, None)
        else: ids[slot] = val
    cur[(slot, code)] = val
print(f"frames={len(frames)}")
# overall interval histogram
iv = [round((frames[i][0]-frames[i-1][0])*1000) for i in range(1, len(frames))]
h = collections.Counter(iv)
print("interval histogram (ms: count):", ' '.join(f"{k}:{h[k]}" for k in sorted(h) if h[k] >= 2))
# per touch: first frame index, intervals of the first 6 frames, max gap inside touch
touches = {}
for i, (t, ids_, ev) in enumerate(frames):
    for s, tid in ids_.items():
        touches.setdefault(tid, []).append(i)
print(f"{'id':>5} {'start_s':>8} {'frames':>6} {'dur_ms':>7}  first intervals (ms)      max_gap_ms  gap_at_frame")
t0 = frames[0][0]
for tid, fi in touches.items():
    ts = [frames[i][0] for i in fi]
    ivs = [round((ts[k]-ts[k-1])*1000) for k in range(1, len(ts))]
    mg = max(ivs) if ivs else 0
    at = ivs.index(mg)+1 if ivs else 0
    print(f"{tid:5d} {ts[0]-t0:8.3f} {len(fi):6d} {(ts[-1]-ts[0])*1000:7.0f}  {str(ivs[:6]):26s} {mg:6d}      {at}")
# gap between previous frame of any kind and each touch's first frame (idle -> first report)
print("idle-to-first-frame gaps (ms):", [round((frames[fi[0]][0]-frames[fi[0]-1][0])*1000) if fi[0] > 0 else None for fi in touches.values()])
