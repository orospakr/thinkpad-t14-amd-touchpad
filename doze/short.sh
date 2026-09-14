#!/bin/bash
# doze/short.sh PREFIX GETID [SECS] : set psmouse_smbus_resume_getid=GETID, rtcwake suspend for SECS (default 240),
# then a gated drag capture (root). Answers: does a short S3 produce the wake jump, with/without the resume GETID?
P=$1; G=$2; S=${3:-240}; D=$(dirname "$0"); LOG=$P.log
echo $G > /sys/module/psmouse/parameters/psmouse_smbus_resume_getid
echo "$(date +%T) resume_getid=$(cat /sys/module/psmouse/parameters/psmouse_smbus_resume_getid); suspending ${S}s (DO NOT TOUCH the pad)" >> $LOG
sync; rtcwake -m mem -s $S >> $LOG 2>&1; sleep 3
echo "$(date +%T) resumed: $(journalctl -k -n 40 --no-pager | grep -o -E 'smbus reconnect.*|resume_reconfig_after.*' | tr '\n' ';')" >> $LOG
$D/gcap.sh $P $LOG 30 || { echo "ABORT: no drags" >> $LOG; exit 1; }
echo "done short" >> $LOG
