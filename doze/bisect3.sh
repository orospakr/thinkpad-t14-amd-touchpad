#!/bin/bash
# doze/bisect3.sh PREFIX : which part of a FIRST pass primes the pad so that a following full pass jumps? (root)
# T1: cure, others(16), full. T2: cure, doze(2), full. T3: cure, full, full (positive control). Final reload.
P=$1; D=$(dirname "$0"); LOG=$P.log; R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
smbok() { grep -q 'F01 ctrl@0014 (0)' $(R)/regdump; }
pass() { echo $1 > /sys/module/rmi_core/parameters/exp_config_mask; echo 1 > $(R)/reconfig; sleep 1; echo "  pass mask=$1: F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-40)" >> $LOG; }
cap() { $D/gcap.sh $P-$1 $LOG 30 || { echo "ABORT: no drags for $1" >> $LOG; exit 1; }; echo "  RESULT $1: $(python3 $D/firstdelta.py $P-$1.evtest | head -1 | cut -d: -f2- | cut -c1-60)" >> $LOG; }
cure() { echo 5 > /sys/module/psmouse/parameters/synaptics_rmi_ps2cmd; sleep 2; echo 1 > /sys/module/rmi_smbus/parameters/clear_state; sleep 1
         smbok || { echo "ABORT: smbus dead after cure" >> $LOG; exit 1; }; pass 4; echo "$(date +%T) cured (GETID + rmi_smb_reset + irq bits)" >> $LOG; }
cure; pass 16; pass 4294967295; cap T1-others-then-full
cure; pass 2;  pass 4294967295; cap T2-doze-then-full
cure; pass 4294967295; pass 4294967295; cap T3-full-then-full
echo "$(date +%T) final reload" >> $LOG; $D/load-all.sh >> $LOG 2>&1; echo "done bisect3" >> $LOG
