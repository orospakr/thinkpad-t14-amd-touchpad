#!/bin/bash
# doze/arm.sh PREFIX : gated baseline capture, then load the psmouse build with synaptics_rmi_ps2cmd, verify, capture again (root)
P=$1; D=$(dirname "$0"); B=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne; LOG=$P.log
$D/gcap.sh $P-base $LOG 30 || { echo "ABORT: no drags" >> $LOG; exit 1; }
echo "$(date +%T) loading psmouse with ps2cmd trigger" >> $LOG
$B/psmouse/load-exp.sh nosleep synaptics_rmi_nosleep=0 synaptics_rmi_doze_interval=6 >> $LOG 2>&1
[ -w /sys/module/psmouse/parameters/synaptics_rmi_ps2cmd ] && echo "trigger present" >> $LOG || echo "TRIGGER MISSING" >> $LOG
$D/gcap.sh $P-after $LOG 30 || { echo "ABORT: no drags after" >> $LOG; exit 1; }
echo "done arm" >> $LOG
