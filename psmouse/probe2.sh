#!/bin/bash
# usage: probe.sh N  -- stock psmouse; cycles until a degraded wake, then: drvctl reconnect (F5 only) -> capture again
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
N=$1; LOG=$P/ab/probe2.log
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
  $P/motw900.sh $P/ab/probe2-$i.txt; { echo "--- probe2-$i"; cat $P/ab/probe2-$i.txt; } >> $LOG
  if degraded $P/ab/probe2-$i.txt; then
    echo "=== $(date) cycle $i DEGRADED -> rmi4_smbus unbind+bind; swipe again" >> $LOG
    echo -n 11-002c > /sys/bus/i2c/drivers/rmi4_smbus/unbind; sleep 1; echo -n 11-002c > /sys/bus/i2c/drivers/rmi4_smbus/bind; sleep 3
    grep Name= /proc/bus/input/devices | grep -q TM3471 || { echo "!!! TM3471 gone after rebind" >> $LOG; break; }
    $P/motw900.sh $P/ab/probe2-$i-afterRebind.txt; { echo "--- probe2-$i-afterRebind"; cat $P/ab/probe2-$i-afterRebind.txt; } >> $LOG
    break
  fi
  sleep 5
done
echo "=== $(date) done probe" >> $LOG
