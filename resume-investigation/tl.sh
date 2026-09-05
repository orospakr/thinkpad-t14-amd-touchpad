#!/bin/bash
OUT=$1
irq(){ grep -E '^ *7:' /proc/interrupts | awk '{s=0;for(i=2;i<=NF-3;i++)s+=$i;print s}'; }
hn(){ grep rmi4_smbus /proc/interrupts | awk '{s=0;for(i=2;i<=NF-3;i++)s+=$i;print s}'; }
dmesg -C
echo 'module i2c_piix4 format "ASF Host Notify from" +p' > /sys/kernel/debug/dynamic_debug/control
rtcwake -m mem -s 15 >/dev/null 2>&1
n=$(grep -A5 'TM3471' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
timeout 90 evtest /dev/input/$n 2>/dev/null | grep -a --line-buffered "Event:" > $OUT.ev &
{
a=$(irq); h=$(hn); e=0
for t in $(seq 1 90); do sleep 1; b=$(irq); g=$(hn); ne=$(wc -l < $OUT.ev); echo "t=$t irq=$((b-a)) hn=$((g-h)) ev=$((ne-e))"; a=$b; h=$g; e=$ne; done
} > $OUT
echo 'module i2c_piix4 format "ASF Host Notify from" -p' > /sys/kernel/debug/dynamic_debug/control
{ echo "== payloads: $(dmesg | grep -c 'Host Notify from')"; dmesg | grep 'Host Notify from' | sed 's/.*ASF/ASF/' | sort | uniq -c | sort -rn | head -4; dmesg | grep -iE "ASF:|stuck|lost the bus|no response|Failed to read"; echo "== ev types"; awk '{print $9,$10,$11}' $OUT.ev | sort | uniq -c | sort -rn | head -8; } >> $OUT
