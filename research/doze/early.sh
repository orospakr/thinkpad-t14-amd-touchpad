#!/bin/bash
# doze/early.sh PREFIX DELAY_MS : GETID reset, rmi_smb_reset, then the full config pass DELAY_MS later; gated capture (root)
P=$1; MS=$2; D=$(dirname "$0"); LOG=$P.log; R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
echo 4294967295 > /sys/module/rmi_core/parameters/exp_config_mask; echo 0 > /sys/module/rmi_core/parameters/exp_doze_if_changed
echo 5 > /sys/module/psmouse/parameters/synaptics_rmi_ps2cmd
echo 1 > /sys/module/rmi_smbus/parameters/clear_state
[ "$MS" -gt 0 ] && sleep $(echo "$MS/1000" | bc -l)
echo 1 > $(R)/reconfig
echo "$(date +%T) GETID, rmi_smb_reset, +${MS}ms full pass: F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-40)" >> $LOG
$D/gcap.sh $P $LOG 30 || { echo "ABORT: no drags" >> $LOG; exit 1; }
echo "  RESULT: $(python3 $D/firstdelta.py $P.evtest | head -1 | cut -d: -f2- | cut -c1-60); $(python3 $D/touchlat.py $P.evtest | sed -n '2p')" >> $LOG; echo "done early" >> $LOG
