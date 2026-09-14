#!/bin/bash
OUT=$1
for f in "collision" "no response" "lost the bus" "stuck full"; do echo "module i2c_piix4 format \"$f\" +p" > /sys/kernel/debug/dynamic_debug/control; done
irq(){ grep -E '^ *7:' /proc/interrupts | awk '{s=0;for(i=2;i<=NF-3;i++)s+=$i;print s}'; }
n=$(grep -A5 'TM3471' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
{
echo "== idle 10s"; a=$(irq); sleep 10; b=$(irq); echo "irq7 idle rate: $(( (b-a)/10 ))/s"
echo "== motion 20s (evtest)"; a=$(irq)
timeout 20 evtest /dev/input/$n 2>/dev/null | grep -a 'SYN_REPORT' | grep -o 'time [0-9.]*' | awk '{print $2}' > $OUT.syn
b=$(irq); echo "irq7 motion rate: $(( (b-a)/20 ))/s"
awk 'NR>1{d=int(($1-p)*1000+0.5); h[d]++; n++} {p=$1} END{print "syn_reports="n; for(k in h) print k"ms", h[k]}' $OUT.syn | sort -k1 -n | head -30
echo "== dmesg since resume"; dmesg | awk '$0 ~ /suspend exit/ {f=1} f' | grep -vE "input:|serio|rmi4_f|registering|usb|hid|Bluetooth|bluetooth|wlan|iwl|amdgpu|thunderbolt|nvme|ata|snd" | tail -40
} > $OUT 2>&1
