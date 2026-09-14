#!/bin/bash
# doze/ps2seq.sh PREFIX : PS/2 command bisect in place after a long suspend (root). Gated drag capture after each step:
# STEPS="base getid detect f5 e8 f6 ff reload" (default: base f5 e8 f6 ff reload); every PS/2 command is followed by an
# rmi_smbus rebind if SMBus reads fail (they always do). Gated drag capture after each step.
P=$1; D=$(dirname "$0"); B=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research
LOG=$P.log; PARAM=/sys/module/psmouse/parameters/synaptics_rmi_ps2cmd
R() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-*; }
ok() { grep Name= /proc/bus/input/devices | grep -q TM3471; }
cap() { $D/gcap.sh $P-$1 $LOG 30 || { echo "ABORT: no drags for $1" >> $LOG; exit 1; }; }
cmd() { echo "$(date +%T) ps2cmd $1 ($2)" >> $LOG; echo $1 > $PARAM; r=$?; echo "  -> rc=$r $(journalctl -k -n 3 --no-pager | grep -o 'synaptics_rmi_ps2cmd.*')" >> $LOG; sleep 2; fixsmb; }
fixsmb() { if smbok; then echo "  smbus alive" >> $LOG; else echo "  SMBUS DEAD -> clear_state" >> $LOG; echo 1 > /sys/module/rmi_smbus/parameters/clear_state; sleep 1; fi; if smbok; then echo "  smbus alive after clear_state" >> $LOG; else echo "  still DEAD -> rmi_smbus rebind (NOTE: rebind leaves F03/TrackPoint dead until a psmouse reload)" >> $LOG; rmmod rmi_smbus; sleep 1; insmod $B/rmi4/smbus/rmi_smbus.ko resume_reconfig_after=1; for i in $(seq 30); do ok && break; sleep 0.5; done; echo "  after rebind: pad $(ok && echo present || echo GONE), smbus $(smbok && echo alive || echo dead)" >> $LOG; fi; }
smbok() { grep -q 'F01 ctrl@0014 (0)' $(R)/regdump; }
[ -w $PARAM ] || { echo "no $PARAM (experimental psmouse with the trigger not loaded)" >> $LOG; exit 1; }
STEPS=${STEPS:-base f5 e8 f6 ff reload}; has() { case " $STEPS " in *" $1 "*) return 0;; esac; return 1; }
has base && cap base
has getid && { cmd 5 F2-GETID; ok || { echo "PAD GONE" >> $LOG; exit 1; }; cap getid; }
has detect && { cmd 6 DETECT; ok || { echo "PAD GONE" >> $LOG; exit 1; }; cap detect; }
has f5 && { cmd 1 F5;  ok || { echo "PAD GONE" >> $LOG; exit 1; }; cap f5; }
has e8 && { cmd 2 E8;  ok || { echo "PAD GONE" >> $LOG; exit 1; }; cap e8; }
has f6 && { cmd 3 F6;  ok || { echo "PAD GONE" >> $LOG; exit 1; }; cap f6; }
has ff && { cmd 4 FF; ok || { echo "PAD GONE after FF" >> $LOG; exit 1; }; cap ff; }
has reload && { echo "$(date +%T) psmouse reload" >> $LOG; $B/psmouse/load-exp.sh nosleep synaptics_rmi_nosleep=0 synaptics_rmi_doze_interval=6 >> $LOG 2>&1
ok || { echo "PAD GONE after reload" >> $LOG; exit 1; }; cap reload; }
echo "done ps2seq" >> $LOG
