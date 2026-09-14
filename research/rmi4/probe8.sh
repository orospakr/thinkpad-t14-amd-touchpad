#!/bin/bash
# usage: probe8.sh DELAY_MS N -- cycles with psmouse reset_reactivate_delay=DELAY; on degraded: arm B (xport_reset) and continue counting
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/rmi4
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/psmouse
DL=$1; N=$2; LOG=$D/probe8-$DL.log
degraded() { awk '/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2} END{exit !(d>c)}' "$1"; }
echo "=== $(date) start probe8 reactivate_delay=$DL N=$N" >> $LOG
bad=0
for i in $(seq 1 $N); do
  $D/load-smbus.sh resume_reactivate_delay_ms=$DL >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  sleep 3
  echo "=== $(date) cycle $i: resumed; swipe the pad" >> $LOG
  $P/motw900.sh $D/probe8-$DL-$i.txt; { echo "--- probe8-$DL-$i"; cat $D/probe8-$DL-$i.txt; } >> $LOG
  if degraded $D/probe8-$DL-$i.txt; then bad=$((bad+1)); echo "=== cycle $i DEGRADED ($bad/$i)" >> $LOG; else echo "=== cycle $i clean ($bad/$i degraded)" >> $LOG; fi
  sleep 5
done
echo "=== $(date) done probe8 reactivate_delay=$DL: $bad/$N degraded" >> $LOG
