#!/bin/bash
# doze/f5probe.sh LOG : does a PS/2 F5 (what stock resume sends) reset the pad's RMI config like GETID does? (root, no hands)
LOG=$1; R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-*)
echo "before F5: F01 $(grep 'F01 ctrl' $R/regdump | cut -c20-40)" >> $LOG
echo 1 > /sys/module/psmouse/parameters/synaptics_rmi_ps2cmd; sleep 2
echo "after F5, before reset: regdump $(grep 'F01 ctrl' $R/regdump | cut -c1-40)" >> $LOG
echo 1 > /sys/module/rmi_smbus/parameters/clear_state; sleep 1
echo "after F5 + rmi_smb_reset: F01 $(grep 'F01 ctrl' $R/regdump | cut -c20-40)" >> $LOG
echo 4294967295 > /sys/module/rmi_core/parameters/exp_config_mask; echo 1 > $R/reconfig; sleep 1
echo "after one config pass: F01 $(grep 'F01 ctrl' $R/regdump | cut -c20-40)" >> $LOG
echo "done f5probe" >> $LOG
