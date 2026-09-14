#!/bin/bash
# doze/cure-getid.sh PREFIX : PS/2 GETID + rmi_smbus clear_state (no re-probe), verify SMBus, gated capture (root)
P=$1; D=$(dirname "$0"); LOG=$P.log; R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-*)
echo 5 > /sys/module/psmouse/parameters/synaptics_rmi_ps2cmd; sleep 2
echo 1 > /sys/module/rmi_smbus/parameters/clear_state; sleep 1
echo "$(date +%T) GETID + clear_state: smbus $(grep -q 'F01 ctrl@0014 (0)' $R/regdump && echo alive || echo DEAD), F01 $(grep 'F01 ctrl' $R/regdump | cut -c20-31), trackpoint $(grep -q TrackPoint /proc/bus/input/devices && echo present || echo GONE)" >> $LOG
grep -q 'F01 ctrl@0014 (0)' $R/regdump || { echo "ABORT: smbus dead" >> $LOG; exit 1; }
$D/gcap.sh $P $LOG 30 || { echo "ABORT: no drags" >> $LOG; exit 1; }
python3 $D/touchlat.py $P.evtest | sed -n '2p' >> $LOG; echo "done cure-getid" >> $LOG
