#!/usr/bin/env python3
"""For each single-finger touch: |delta| (units) of frames 1..5 after landing, and frames until |delta|>=6 (0.5 mm)."""
import sys, re, statistics
for f in sys.argv[1:]:
    ids={}; cur={}; slot=0; pos={}; touches={}; order=[]
    for line in open(f, errors='replace'):
        m=re.match(r'Event: time (\d+\.\d+), (.*)', line)
        if not m: continue
        t=float(m.group(1)); rest=m.group(2)
        if 'SYN_REPORT' in rest:
            for s,tid in ids.items():
                p=pos.get(s)
                if p and 'x' in p and 'y' in p:
                    touches.setdefault(tid,[]).append((t,p['x'],p['y'],len(ids)))
            cur={}; continue
        m2=re.search(r'\((\w+)\), value (-?\d+)', rest)
        if not m2: continue
        code,val=m2.group(1),int(m2.group(2))
        if code=='ABS_MT_SLOT': slot=val
        elif code=='ABS_MT_TRACKING_ID':
            if val<0: ids.pop(slot,None); pos.pop(slot,None)
            else: ids[slot]=val; pos[slot]={}; order.append(val)
        elif code=='ABS_MT_POSITION_X': pos.setdefault(slot,{})['x']=val
        elif code=='ABS_MT_POSITION_Y': pos.setdefault(slot,{})['y']=val
    rows=[]
    for tid in order:
        fr=touches.get(tid,[])
        if len(fr)<8 or any(n!=1 for _,_,_,n in fr[:8]): continue   # single-finger drags only
        d=[round(((fr[i][1]-fr[i-1][1])**2+(fr[i][2]-fr[i-1][2])**2)**0.5) for i in range(1,min(len(fr),7))]
        first=next((i+1 for i,v in enumerate(d) if v>=6), None)
        rows.append((tid,d,first))
    if not rows: print(f"{f}: no single-finger drags"); continue
    f1=[r[1][0] for r in rows]; 
    print(f"{f}: {len(rows)} drags; frame1 |delta| median {statistics.median(f1):.0f} units (min {min(f1)} max {max(f1)}); frames-to-0.5mm: {[r[2] for r in rows]}")
    for r in rows[:6]: print(f"   id{r[0]} deltas {r[1]}")
