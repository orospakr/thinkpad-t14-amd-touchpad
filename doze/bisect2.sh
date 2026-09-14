#!/bin/bash
# doze/bisect2.sh PREFIX : which config write causes the jump when it comes AFTER the F01 ctrl0 write (move-form resume order)?
# S0: cure, ctrl0, full pass (positive control). S1..S3: cure, ctrl0, then doze | F12 ctrl regs | others. Final reload. (root)
P=$1; D=$(dirname "$0"); LOG=$P.log; R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
smbok() { grep -q 'F01 ctrl@0014 (0)' $(R)/regdump; }
pass() { echo $1 > /sys/module/rmi_core/parameters/exp_config_mask; echo 1 > $(R)/reconfig; sleep 1; echo "  pass mask=$1: F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-40)" >> $LOG; }
cap() { $D/gcap.sh $P-$1 $LOG 30 || { echo "ABORT: no drags for $1" >> $LOG; exit 1; }; echo "  RESULT $1: $(python3 $D/firstdelta.py $P-$1.evtest | head -1 | cut -d: -f2- | cut -c1-60)" >> $LOG; }
cure() { echo 5 > /sys/module/psmouse/parameters/synaptics_rmi_ps2cmd; sleep 2; echo 1 > /sys/module/rmi_smbus/parameters/clear_state; sleep 1
         smbok || { echo "ABORT: smbus dead after cure" >> $LOG; exit 1; }; pass 4; echo "$(date +%T) cured (GETID + rmi_smb_reset + irq bits)" >> $LOG; }
cure; pass 1; pass 4294967295; cap S0-ctrl0-then-full
cure; pass 1; pass 2;  cap S1-ctrl0-then-doze
cure; pass 1; pass 8;  cap S2-ctrl0-then-f12ctrl
cure; pass 1; pass 16; cap S3-ctrl0-then-others
echo "$(date +%T) final reload" >> $LOG; $D/load-all.sh >> $LOG 2>&1; echo "done bisect2" >> $LOG
