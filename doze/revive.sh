#!/bin/bash
# doze/revive.sh OUT : reconfig -> regdump -> 8 s evtest; if no frames, reload the experimental stack (root)
OUT=$1; R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-*); D=$(dirname "$0")
echo 1 > $R/reconfig; sleep 1
cat $R/regdump > $OUT.regdump
n=$(grep -A5 'TM3471' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
timeout --foreground 8 stdbuf -o0 evtest /dev/input/$n 2>/dev/null | grep -a -c SYN_REPORT > $OUT.frames
echo "after reconfig: $(cat $OUT.frames) frames" >> $OUT.log
if [ "$(cat $OUT.frames)" = 0 ]; then
  $D/../psmouse/load-exp.sh nosleep synaptics_rmi_nosleep=0 synaptics_rmi_doze_interval=6 >> $OUT.log 2>&1
fi
echo "done revive" >> $OUT.log
