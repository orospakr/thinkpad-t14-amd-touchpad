#!/usr/bin/env python3
# per-touch summary from an evtest log (as written by pressure-capture.sh): begin, duration, tool, max pressure, max major
import sys, re
slot = 0; touches = {}; order = []; cur = {}
tool = {}; 
for line in open(sys.argv[1], errors='replace'):
    m = re.match(r'Event: time ([0-9.]+), type \d+ \((\w+)\), code \d+ \((\w+)\), value (-?\d+)', line)
    if not m: continue
    t, typ, code, val = float(m.group(1)), m.group(2), m.group(3), int(m.group(4))
    if code == 'ABS_MT_SLOT': slot = val
    elif code == 'ABS_MT_TRACKING_ID':
        if val >= 0:
            cur[slot] = dict(id=val, t0=t, t1=t, tool=tool.get(slot, 0), pmax=0, mmax=0, n=0); order.append(cur[slot])
        elif slot in cur:
            cur[slot]['t1'] = t; del cur[slot]
    elif code == 'ABS_MT_TOOL_TYPE':
        tool[slot] = val
        if slot in cur: cur[slot]['tool'] = val
    elif code == 'ABS_MT_PRESSURE' and slot in cur:
        cur[slot]['pmax'] = max(cur[slot]['pmax'], val); cur[slot]['n'] += 1; cur[slot]['t1'] = t
    elif code == 'ABS_MT_TOUCH_MAJOR' and slot in cur:
        cur[slot]['mmax'] = max(cur[slot]['mmax'], val)
t0 = order[0]['t0'] if order else 0
print(f"{'id':>4} {'start':>7} {'dur_ms':>7} {'tool':>5} {'pmax':>5} {'major':>6} {'frames':>6}   (slots: needs ABS_MT_SLOT in the log; older logs merge slots)")
for o in order:
    print(f"{o['id']:>4} {o['t0']-t0:7.2f} {(o['t1']-o['t0'])*1000:7.0f} {'PALM' if o['tool']==2 else 'fingr':>5} {o['pmax']:>5} {o['mmax']:>6} {o['n']:>6}")
