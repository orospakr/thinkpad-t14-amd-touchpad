#!/bin/bash
# doze/seq.sh PREFIX : baseline -> xport_reset -> rmi_smbus rebind -> psmouse reload, drag capture after each (root)
P=$1; D=$(dirname "$0"); B=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research
LOG=$P.log; R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
ok() { grep Name= /proc/bus/input/devices | grep -q TM3471; }
cap() { $D/gcap.sh $P-$1 $LOG 30 || { echo "ABORT: no drags for $1" >> $LOG; exit 1; }; }
cap base
echo "$(date +%T) xport_reset" >> $LOG; echo 1 > $(R)/xport_reset; sleep 2; ok || { echo "PAD GONE after xport_reset" >> $LOG; exit 1; }
cap xport
echo "$(date +%T) rmi_smbus rebind" >> $LOG; rmmod rmi_smbus; sleep 1; insmod $B/rmi4/smbus/rmi_smbus.ko resume_reconfig_after=1
for i in $(seq 30); do ok && break; sleep 0.5; done; ok || { echo "PAD GONE after rmi_smbus rebind" >> $LOG; exit 1; }
cap smbrebind
echo "$(date +%T) psmouse reload" >> $LOG; $B/psmouse/load-exp.sh nosleep synaptics_rmi_nosleep=0 synaptics_rmi_doze_interval=6 >> $LOG 2>&1
ok || { echo "PAD GONE after reload" >> $LOG; exit 1; }
cap reload
echo "done seq" >> $LOG
