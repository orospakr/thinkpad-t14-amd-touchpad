#!/bin/bash
# usage: probe.sh N  -- stock psmouse; cycles until a degraded wake, then: drvctl reconnect (F5 only) -> capture again
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
N=$1; LOG=$P/ab/probe.log
degraded() { awk '/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2} END{exit !(d>c)}' "$1"; }
echo "=== $(date) start probe N=$N srcversion=$(cat /sys/module/psmouse/srcversion)" >> $LOG
for i in $(seq 1 $N); do
  $P/load-intree.sh stock >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  sleep 3
  echo "=== $(date) cycle $i: resumed; swipe the pad" >> $LOG
  $P/motw900.sh $P/ab/probe-$i.txt; { echo "--- probe-$i"; cat $P/ab/probe-$i.txt; } >> $LOG
  if degraded $P/ab/probe-$i.txt; then
    echo "=== $(date) cycle $i DEGRADED -> drvctl reconnect (F5); swipe again" >> $LOG
    echo -n reconnect > /sys/bus/serio/devices/serio1/drvctl; sleep 2
    grep Name= /proc/bus/input/devices | grep -q TM3471 || { echo "!!! TM3471 gone after reconnect" >> $LOG; break; }
    $P/motw900.sh $P/ab/probe-$i-afterF5.txt; { echo "--- probe-$i-afterF5"; cat $P/ab/probe-$i-afterF5.txt; } >> $LOG
    break
  fi
  sleep 5
done
echo "=== $(date) done probe" >> $LOG
