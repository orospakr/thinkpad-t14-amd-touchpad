#!/bin/bash
# usage: cycle.sh stock|patched N  (re-attaches before each suspend so cycles are independent)   -- N suspend cycles (90 s RTC alarm), touch-triggered 20 s capture after each wake
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/psmouse
TAG=$1; N=$2; LOG=$P/ab/$TAG.log
echo "=== $(date) start $TAG N=$N srcversion=$(cat /sys/module/psmouse/srcversion)" >> $LOG
echo "cycle 0 (pre-suspend baseline): swipe the pad" >> $LOG
$P/motw900.sh $P/ab/$TAG-0.txt; echo "--- $TAG-0"; cat $P/ab/$TAG-0.txt >> $LOG
for i in $(seq 1 $N); do
  $P/load.sh $TAG >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  sleep 3
  echo "=== $(date) cycle $i: resumed; swipe the pad" >> $LOG
  grep Name= /proc/bus/input/devices | grep -q TM3471 || { echo "!!! TM3471 gone" >> $LOG; break; }
  $P/motw900.sh $P/ab/$TAG-$i.txt
  { echo "--- $TAG-$i"; cat $P/ab/$TAG-$i.txt; } >> $LOG
  sleep 5
done
echo "=== $(date) done $TAG" >> $LOG
