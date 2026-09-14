#!/bin/bash
# doze/seq7.sh PREFIX : next broken resume, in place (root). base -> F01 hwreset + clear_state (SMBus-only fix candidate)
# -> capture; if not cured: F2 GETID + clear_state -> capture; if still not cured: psmouse reload -> capture.
P=$1; D=$(dirname "$0"); B=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne; LOG=$P.log
PARAM=/sys/module/psmouse/parameters/synaptics_rmi_ps2cmd; CLR=/sys/module/rmi_smbus/parameters/clear_state
R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
ok() { grep Name= /proc/bus/input/devices | grep -q TM3471; }
smbok() { grep -q 'F01 ctrl@0014 (0)' $(R)/regdump; }
cap() { $D/gcap.sh $P-$1 $LOG 30 || { echo "ABORT: no drags for $1" >> $LOG; exit 1; }; }
cured() { python3 $D/firstdelta.py $P-$1.evtest | head -1 | grep -q 'median 0 units'; }
clr() { echo 1 > $CLR; sleep 1; echo "  after clear_state: smbus $(smbok && echo alive || echo DEAD), F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-31)" >> $LOG; }
reload() { echo "$(date +%T) psmouse reload" >> $LOG; $B/psmouse/load-exp.sh nosleep synaptics_rmi_nosleep=0 synaptics_rmi_doze_interval=6 >> $LOG 2>&1; }
[ -w $CLR ] && [ -w $PARAM ] || { echo "triggers missing" >> $LOG; exit 1; }
cap base
echo "$(date +%T) F01 hwreset" >> $LOG; echo 1 > $(R)/hwreset; sleep 2; clr
if ! smbok; then echo "  SMBus still dead after hwreset+clear_state -> reload" >> $LOG; reload; cap hwreset-reload; echo "done seq7" >> $LOG; exit 0; fi
ok || { echo "PAD GONE" >> $LOG; exit 1; }
# the F01 reset wipes the config; run the config pass so doze regs etc. are back before measuring
echo 1 > $(R)/reconfig; sleep 1; echo "  after reconfig: F01 $(grep 'F01 ctrl' $(R)/regdump | cut -c20-31), fn12 irq $(grep fn12 /proc/interrupts | head -1 | awk '{print $2}')" >> $LOG
cap hwreset
if cured hwreset; then echo "hwreset CURED" >> $LOG; echo "done seq7" >> $LOG; exit 0; fi
echo "$(date +%T) ps2cmd 5 (F2-GETID)" >> $LOG; echo 5 > $PARAM; sleep 2; clr
smbok || { echo "  dead after GETID+clear_state -> reload" >> $LOG; reload; cap getid-reload; echo "done seq7" >> $LOG; exit 0; }
cap getid
if cured getid; then echo "getid+clear_state CURED" >> $LOG; else echo "getid+clear_state NOT cured" >> $LOG; reload; cap reload; fi
echo "done seq7" >> $LOG
