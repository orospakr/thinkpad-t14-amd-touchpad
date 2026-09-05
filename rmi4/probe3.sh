#!/bin/bash
# usage: probe3.sh N -- cycles (resume_reconfig=0); on degraded: regdump, rebind rmi4_smbus, regdump, capture; then stop
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/rmi4
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
N=$1; LOG=$D/probe3.log
degraded() { awk '/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2} END{exit !(d>c)}' "$1"; }
echo "=== $(date) start probe3 N=$N resume_reconfig=$(cat /sys/module/rmi_core/parameters/resume_reconfig)" >> $LOG
echo "--- regdump clean (pre)" >> $LOG; $D/dump.sh >> $LOG 2>&1
for i in $(seq 1 $N); do
  $D/load-rmi.sh patched >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  sleep 3
  echo "=== $(date) cycle $i: resumed; swipe the pad" >> $LOG
  $P/motw900.sh $D/probe3-$i.txt; { echo "--- probe3-$i"; cat $D/probe3-$i.txt; } >> $LOG
  echo "--- regdump after cycle $i" >> $LOG; $D/dump.sh >> $LOG 2>&1
  if degraded $D/probe3-$i.txt; then
    echo "=== $(date) cycle $i DEGRADED -> rebind rmi4_smbus; swipe again" >> $LOG
    echo -n 11-002c > /sys/bus/i2c/drivers/rmi4_smbus/unbind; sleep 1; echo -n 11-002c > /sys/bus/i2c/drivers/rmi4_smbus/bind; sleep 3
    $P/motw900.sh $D/probe3-$i-afterRebind.txt; { echo "--- probe3-$i-afterRebind"; cat $D/probe3-$i-afterRebind.txt; } >> $LOG
    echo "--- regdump after rebind" >> $LOG; $D/dump.sh >> $LOG 2>&1
    break
  fi
  sleep 5
done
echo "=== $(date) done probe3" >> $LOG
