#!/bin/bash
# doze/ctrl.sh PREFIX RECONFIG GETID [SECS] : set rmi_smbus resume_reconfig_after=RECONFIG and psmouse resume GETID=GETID,
# rtcwake suspend SECS (default 240), gated drag capture (root). Control experiments for the wake jump.
P=$1; RC=$2; G=$3; S=${4:-240}; D=$(dirname "$0"); LOG=$P.log
echo $RC > /sys/module/rmi_smbus/parameters/resume_reconfig_after; echo $G > /sys/module/psmouse/parameters/psmouse_smbus_resume_getid
echo "$(date +%T) resume_reconfig_after=$(cat /sys/module/rmi_smbus/parameters/resume_reconfig_after) resume_getid=$(cat /sys/module/psmouse/parameters/psmouse_smbus_resume_getid) doze_interval=$(cat /sys/module/psmouse/parameters/synaptics_rmi_doze_interval); suspending ${S}s (DO NOT TOUCH the pad)" >> $LOG
sync; rtcwake -m mem -s $S >> $LOG 2>&1; sleep 3
echo "$(date +%T) resumed: $(journalctl -k -n 40 --no-pager | grep -o -E 'smbus reconnect.*|resume_reconfig_after.*' | tr '\n' ';')" >> $LOG
$D/gcap.sh $P $LOG 30 || { echo "ABORT: no drags" >> $LOG; exit 1; }
python3 $D/touchlat.py $P.evtest | sed -n '2p' >> $LOG
echo "done ctrl" >> $LOG
