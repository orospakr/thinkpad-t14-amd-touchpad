#!/bin/bash
# doze/bisect.sh PREFIX [MASKS] : for each config-pass write mask: cure (GETID + clear_state), set exp_config_mask,
# run the config pass, gated capture. GETID resets the pad config (IRQ mask 00), so the cure also sets the F12 irq bits
# (mask 4). Ends with a cure-only control capture and a full reload (TrackPoint). (root)
P=$1; MASKS=${2:-1 2 8 4 16}; D=$(dirname "$0"); LOG=$P.log
R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
smbok() { grep -q 'F01 ctrl@0014 (0)' $(R)/regdump; }
cap() { $D/gcap.sh $P-$1 $LOG 30 || { echo "ABORT: no drags for $1" >> $LOG; exit 1; }; python3 $D/firstdelta.py $P-$1.evtest | head -1 | cut -d: -f2- >> $LOG; }
cure() { echo 5 > /sys/module/psmouse/parameters/synaptics_rmi_ps2cmd; sleep 2; echo 1 > /sys/module/rmi_smbus/parameters/clear_state; sleep 1
         smbok || { echo "ABORT: smbus dead after cure" >> $LOG; exit 1; }
         echo 4 > /sys/module/rmi_core/parameters/exp_config_mask; echo 1 > $(R)/reconfig; sleep 1
         echo "$(date +%T) cure: GETID + rmi_smb_reset + F12 irq bits -> F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-40)" >> $LOG; }
for M in $MASKS; do
  cure
  echo $M > /sys/module/rmi_core/parameters/exp_config_mask; echo 1 > $(R)/reconfig; sleep 1
  echo "$(date +%T) config pass with mask=$M: F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-40)" >> $LOG
  cap mask$M
done
echo 4294967295 > /sys/module/rmi_core/parameters/exp_config_mask
cure; cap control
echo "$(date +%T) final reload (restores TrackPoint + full config)" >> $LOG; $D/load-all.sh >> $LOG 2>&1
echo "done bisect" >> $LOG
