#!/bin/bash
# doze/reconfig-now.sh PREFIX : run the RMI config pass (sysfs reconfig) on the awake sensor, then gated capture (root)
P=$1; D=$(dirname "$0"); LOG=$P.log; R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-*)
echo "$(date +%T) reconfig (config pass, sensor awake, $(( $(date +%s) - $(date -d "$(journalctl -k --no-pager | grep 'suspend exit' | tail -1 | awk '{print $1,$2,$3}')" +%s) )) s after resume)" >> $LOG
echo 1 > $R/reconfig; sleep 1; echo "  F01 $(grep 'F01 ctrl' $R/regdump | cut -c20-40)" >> $LOG
$D/gcap.sh $P $LOG 30 || { echo "ABORT: no drags" >> $LOG; exit 1; }
python3 $D/touchlat.py $P.evtest | sed -n '2p' >> $LOG; echo "done reconfig-now" >> $LOG
