#!/bin/bash
# doze/seq6.sh PREFIX : in-place test of why GETID-at-resume fails (root). base -> GETID + xport_reset (resume-style
# transport reset + config, rebind only if still dead) -> capture; if cured: F5 + xport_reset -> capture; else rebind -> capture
P=$1; D=$(dirname "$0"); B=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne; LOG=$P.log
PARAM=/sys/module/psmouse/parameters/synaptics_rmi_ps2cmd
R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
ok() { grep Name= /proc/bus/input/devices | grep -q TM3471; }
smbok() { grep -q 'F01 ctrl@0014 (0)' $(R)/regdump; }
cap() { $D/gcap.sh $P-$1 $LOG 30 || { echo "ABORT: no drags for $1" >> $LOG; exit 1; }; }
cured() { python3 $D/firstdelta.py $P-$1.evtest | head -1 | grep -q 'median 0 units'; }
cmd() { echo "$(date +%T) ps2cmd $1 ($2)" >> $LOG; echo $1 > $PARAM; echo "  -> rc=$? $(journalctl -k -n 3 --no-pager | grep -o 'synaptics_rmi_ps2cmd.*')" >> $LOG; sleep 2; }
xport() { echo "$(date +%T) xport_reset" >> $LOG; echo 1 > $(R)/xport_reset; sleep 2; echo "  smbus $(smbok && echo alive || echo DEAD)" >> $LOG; }
rebind() { echo "$(date +%T) rmi_smbus rebind" >> $LOG; rmmod rmi_smbus; sleep 1; insmod $B/rmi4/smbus/rmi_smbus.ko resume_reconfig_after=1; for i in $(seq 30); do ok && break; sleep 0.5; done; echo "  pad $(ok && echo present || echo GONE), smbus $(smbok && echo alive || echo DEAD)" >> $LOG; }
cap base
cmd 5 F2-GETID; xport; smbok || rebind; ok || { echo "PAD GONE" >> $LOG; exit 1; }
cap getid-xport
if cured getid-xport; then
  echo "getid+xport CURED -> now F5" >> $LOG
  cmd 1 F5; xport; smbok || rebind; ok || { echo "PAD GONE" >> $LOG; exit 1; }
  cap f5-after
else
  echo "getid+xport NOT cured -> rebind" >> $LOG
  rebind; ok || { echo "PAD GONE" >> $LOG; exit 1; }
  cap getid-rebind
fi
echo "done seq6" >> $LOG
