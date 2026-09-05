#!/bin/bash
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
LOG=$P/ab/f4f5.log
step() { echo "=== $(date) $1: swipe the pad" >> $LOG; $P/motw900.sh $P/ab/f4f5-$1.txt; { echo "--- $1"; cat $P/ab/f4f5-$1.txt; } >> $LOG; }
step baseline
echo "=== sending F4" >> $LOG; python3 $P/ps2cmd.py F4 >> $LOG 2>&1; sleep 1
step afterF4
echo "=== sending F5" >> $LOG; python3 $P/ps2cmd.py F5 >> $LOG 2>&1; sleep 1
step afterF5
grep Name= /proc/bus/input/devices | grep TM3471 >> $LOG
echo "=== $(date) done f4f5" >> $LOG
