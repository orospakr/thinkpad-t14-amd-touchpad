#!/bin/bash
# dump ASF regs at 0xB20 window (IO), 5 samples 200ms apart, plus irq7 count + pm decodeen
python3 - <<'PY'
import os,time,struct
fd=os.open('/dev/port',os.O_RDONLY)
def rd(p): os.lseek(fd,p,0); return os.read(fd,1)[0]
names={0x00:'HSTSTS',0x02:'HSTCNT',0x07:'ASFINDEX/BLKDAT',0x09:'LISADDR',0x0a:'ASFSTA',0x0d:'SLVSTA',0x11:'RWPTR',0x13:'BNKSEL',0x15:'SLVEN'}
def irq():
    for l in open('/proc/interrupts'):
        if l.strip().startswith('7:'): return sum(int(x) for x in l.split()[1:17])
for i in range(5):
    r={n:rd(0xb20+o) for o,n in names.items()}
    print(f"irq7={irq()} "+" ".join(f"{n}={v:02x}" for n,v in r.items()))
    time.sleep(0.2)
PY
