#!/bin/bash
# doze/double.sh PREFIX : is it a config pass on an already-configured awake pad? (root)
# E1: full config pass on the just-reloaded pad -> capture. E2: cure, one full pass -> capture. E3: second full pass -> capture. Reload.
P=$1; D=$(dirname "$0"); LOG=$P.log; R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
smbok() { grep -q 'F01 ctrl@0014 (0)' $(R)/regdump; }
cap() { $D/gcap.sh $P-$1 $LOG 30 || { echo "ABORT: no drags for $1" >> $LOG; exit 1; }; echo "  $1: $(python3 $D/firstdelta.py $P-$1.evtest | head -1 | cut -d: -f2- | cut -c1-60)" >> $LOG; }
full() { echo 4294967295 > /sys/module/rmi_core/parameters/exp_config_mask; echo 1 > $(R)/reconfig; sleep 1; echo "$(date +%T) full config pass ($1): F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-40)" >> $LOG; }
cure() { echo 5 > /sys/module/psmouse/parameters/synaptics_rmi_ps2cmd; sleep 2; echo 1 > /sys/module/rmi_smbus/parameters/clear_state; sleep 1
         smbok || { echo "ABORT: smbus dead after cure" >> $LOG; exit 1; }
         echo 4 > /sys/module/rmi_core/parameters/exp_config_mask; echo 1 > $(R)/reconfig; sleep 1
         echo "$(date +%T) cure: GETID + rmi_smb_reset + F12 irq bits -> F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-40)" >> $LOG; }
full "E1: on the reloaded pad"; cap E1
cure; full "E2: first after cure"; cap E2
full "E3: second after cure"; cap E3
echo "$(date +%T) final reload" >> $LOG; $D/load-all.sh >> $LOG 2>&1
echo "done double" >> $LOG
