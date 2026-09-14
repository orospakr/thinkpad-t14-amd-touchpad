#!/usr/bin/env python3
# per-frame slot state from an evtest log with ABS_MT_SLOT; prints frames with >=2 fingers, flags separation jumps
import sys, re, math
slot=0; st={}; t=None; frames=[]
for line in open(sys.argv[1], errors='replace'):
    m=re.match(r'Event: time ([0-9.]+), type \d+ \((\w+)\), code \d+ \((\w+)\), value (-?\d+)', line)
    if m:
        t=float(m.group(1)); code=m.group(3); val=int(m.group(4))
        if code=='ABS_MT_SLOT': slot=val
        elif code=='ABS_MT_TRACKING_ID':
            if val>=0: st[slot]={'id':val,'x':None,'y':None,'p':0,'new':True}
            else: st.pop(slot,None)
        elif slot in st:
            if code=='ABS_MT_POSITION_X': st[slot]['x']=val
            elif code=='ABS_MT_POSITION_Y': st[slot]['y']=val
            elif code=='ABS_MT_PRESSURE': st[slot]['p']=val
        continue
    if 'SYN_REPORT' in line and t is not None:
        snap={s:dict(v) for s,v in st.items()}
        frames.append((t,snap))
        for v in st.values(): v['new']=False
t0=frames[0][0] if frames else 0; prev=None; ep=0
for t,snap in frames:
    ids=sorted(snap)
    if len(ids)>=2:
        a,b=snap[ids[0]],snap[ids[1]]
        if None in (a['x'],a['y'],b['x'],b['y']): continue
        d=math.hypot(a['x']-b['x'],a['y']-b['y'])
        flag=''
        if prev is None: ep+=1; flag='  <-- 2fg begin (episode %d)'%ep
        elif d>prev*1.3 or d<prev*0.7: flag='  <-- SEPARATION JUMP %.0f -> %.0f'%(prev,d)
        if flag or (prev and abs(d-prev)>60):
            print(f"{t-t0:8.3f}s id{a['id']}({a['x']:5d},{a['y']:5d},p{a['p']:3d}) id{b['id']}({b['x']:5d},{b['y']:5d},p{b['p']:3d}) sep={d:6.0f}{flag}")
        prev=d
    else: prev=None
