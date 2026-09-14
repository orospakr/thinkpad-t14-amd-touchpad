#!/bin/bash
# doze/diag.sh OUT [DUR] : regdump + raw evtest capture of the TM3471 (root)
OUT=$1; DUR=${2:-40}
D=$(dirname "$OUT")
cat /sys/bus/i2c/devices/11-002c/rmi4-*/regdump > $OUT.regdump
grep -E '^ *(7|95|99|102):' /proc/interrupts | awk '{print $1, $2+$3+$4+$5+$6+$7+$8+$9}' > $OUT.irq0
n=$(grep -A5 'TM3471' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
timeout --foreground $DUR stdbuf -o0 evtest /dev/input/$n 2>/dev/null | grep -a --line-buffered -E 'SYN_REPORT|ABS_MT_SLOT|ABS_MT_TRACKING_ID|ABS_MT_POSITION|BTN_TOUCH' > $OUT.evtest
grep -E '^ *(7|95|99|102):' /proc/interrupts | awk '{print $1, $2+$3+$4+$5+$6+$7+$8+$9}' > $OUT.irq1
echo "done diag $OUT" >> $OUT.log
