#!/bin/bash
# doze/cure.sh TRIGGER OUT : poke the experimental rmi_core sysfs trigger (reconfig|xport_reset|hwreset),
# check the pad survived, then run diag.sh for a drag capture (root)
T=$1; OUT=$2; R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-*)
echo "$(date +%T) trigger $T" >> $OUT.log
echo 1 > $R/$T; sleep 2
grep Name= /proc/bus/input/devices | grep -q TM3471 || { echo "PAD GONE after $T" >> $OUT.log; exit 1; }
echo "$(date +%T) pad present; capture" >> $OUT.log
exec "$(dirname "$0")/diag.sh" $OUT ${3:-30}
