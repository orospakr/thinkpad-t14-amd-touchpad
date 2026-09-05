#!/usr/bin/env python3
# send one command byte to the i8042 AUX (mouse) port: D4 -> 0x64, byte -> 0x60
import os, sys, time
b = int(sys.argv[1], 16)
fd = os.open('/dev/port', os.O_RDWR)
def st():
    os.lseek(fd, 0x64, 0); return os.read(fd, 1)[0]
def wait_ibf():
    for _ in range(10000):
        if not (st() & 2): return True
        time.sleep(0.0001)
    return False
def out(port, v):
    assert wait_ibf(), "IBF stuck"
    os.lseek(fd, port, 0); os.write(fd, bytes([v]))
out(0x64, 0xD4); out(0x60, b)
time.sleep(0.05)
print("sent %02X, status=%02X" % (b, st()))
