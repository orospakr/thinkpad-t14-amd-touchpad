#!/bin/bash
# usage: probe9.sh N [START] [WAIT_S] -- cycles numbered START..START+N-1 (default 1); after each wake: WAIT_S (default 60) untouched, then arm B (xport_reset), then capture; if degraded: arm B again, capture
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/rmi4
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/psmouse
N=$1; S=${2:-1}; W=${3:-60}; T=probe9; [ "$W" != 60 ] && T=probe9-w$W; LOG=$D/$T.log; bad=0
degraded() { awk '/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2} END{exit !(d>c)}' "$1"; }
f12() { awk '/fn12/{s=0; for(i=2;i<=NF;i++) if($i~/^[0-9]+$/) s+=$i; else break; t+=s} END{print t}' /proc/interrupts; }
echo "=== $(date) start probe9 N=$N START=$S WAIT=$W (late xport_reset)" >> $LOG
for i in $(seq $S $((S+N-1))); do
  $D/load-smbus.sh >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  a=$(f12); echo "=== $(date) cycle $i: resumed; DO NOT TOUCH for $W s" >> $LOG; sleep $W; b=$(f12)
  echo "=== f12 irqs during wait: $((b-a))" >> $LOG
  R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-* | head -1); echo 1 > $R/xport_reset; sleep 1
  echo "=== $(date) cycle $i: armB done (untouched); swipe the pad" >> $LOG
  $P/motw900.sh $D/$T-$i.txt; { echo "--- $T-$i"; cat $D/$T-$i.txt; } >> $LOG
  if degraded $D/$T-$i.txt; then
    echo "=== cycle $i DEGRADED after untouched armB -> armB again; swipe" >> $LOG
    echo 1 > $R/xport_reset; sleep 1
    $P/motw60.sh $D/$T-$i-b.txt; { echo "--- $T-$i-b"; cat $D/$T-$i-b.txt; } >> $LOG
    degraded $D/$T-$i-b.txt && echo "=== still DEGRADED after touched armB" >> $LOG || echo "=== CLEAN after touched armB" >> $LOG
    bad=$((bad+1))
  else echo "=== cycle $i clean after untouched armB" >> $LOG; fi
  sleep 5
done
echo "=== $(date) done probe9 WAIT=$W: $bad/$N degraded" >> $LOG
