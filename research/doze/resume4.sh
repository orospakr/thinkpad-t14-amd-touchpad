#!/bin/bash
# one-off: revive SMBus after the F5 kill, then continue the bisect from the f5 capture
B=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research; LOG=$B/doze/long4.log
echo "$(date +%T) manual: SMBUS DEAD after F5 -> rmi_smbus rebind" >> $LOG
rmmod rmi_smbus; sleep 1; insmod $B/rmi4/smbus/rmi_smbus.ko resume_reconfig_after=1
for i in $(seq 30); do grep Name= /proc/bus/input/devices | grep -q TM3471 && break; sleep 0.5; done
echo "  after rebind: pad $(grep Name= /proc/bus/input/devices | grep -q TM3471 && echo present || echo GONE), smbus $(grep -q 'F01 ctrl@0014 (0)' /sys/bus/i2c/devices/11-002c/rmi4-*/regdump && echo alive || echo dead)" >> $LOG
$B/doze/gcap.sh $B/doze/long4-f5 $LOG 30 || { echo "ABORT: no drags for f5" >> $LOG; exit 1; }
STEPS="e8 f6 ff reload" exec $B/doze/ps2seq.sh $B/doze/long4
