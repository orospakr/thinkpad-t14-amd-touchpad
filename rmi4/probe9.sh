#!/bin/bash
# usage: probe9.sh N -- after each wake: 60 s untouched, then arm B (xport_reset), then capture; if degraded: arm B again, capture
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/rmi4
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
N=$1; LOG=$D/probe9.log
degraded() { awk '/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2} END{exit !(d>c)}' "$1"; }
f12() { awk '/fn12/{s=0; for(i=2;i<=NF;i++) if($i~/^[0-9]+$/) s+=$i; else break; t+=s} END{print t}' /proc/interrupts; }
echo "=== $(date) start probe9 N=$N" >> $LOG
for i in $(seq 1 $N); do
  $D/load-smbus.sh >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  a=$(f12); echo "=== $(date) cycle $i: resumed; DO NOT TOUCH for 60 s" >> $LOG; sleep 60; b=$(f12)
  echo "=== f12 irqs during wait: $((b-a))" >> $LOG
  R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-* | head -1); echo 1 > $R/xport_reset; sleep 1
  echo "=== $(date) cycle $i: armB done (untouched); swipe the pad" >> $LOG
  $P/motw900.sh $D/probe9-$i.txt; { echo "--- probe9-$i"; cat $D/probe9-$i.txt; } >> $LOG
  if degraded $D/probe9-$i.txt; then
    echo "=== cycle $i DEGRADED after untouched armB -> armB again; swipe" >> $LOG
    echo 1 > $R/xport_reset; sleep 1
    $P/motw60.sh $D/probe9-$i-b.txt; { echo "--- probe9-$i-b"; cat $D/probe9-$i-b.txt; } >> $LOG
    degraded $D/probe9-$i-b.txt && echo "=== still DEGRADED after touched armB" >> $LOG || echo "=== CLEAN after touched armB" >> $LOG
    break
  else echo "=== cycle $i clean after untouched armB" >> $LOG; fi
  sleep 5
done
echo "=== $(date) done probe9" >> $LOG
