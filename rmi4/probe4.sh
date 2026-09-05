#!/bin/bash
# usage: probe4.sh N -- cycles; log rmi4 irq counters around each capture; on degraded: rebind TrackPoint psmouse on the F03 serio, capture; if still degraded, rebind rmi4_smbus
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/rmi4
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
N=$1; LOG=$D/probe4.log
degraded() { awk '/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2} END{exit !(d>c)}' "$1"; }
irqs() { echo "--- irqs $1" >> $LOG; grep -i "rmi4\|piix4" /proc/interrupts | awk '{s=0; for(i=2;i<=NF;i++) if($i~/^[0-9]+$/) s+=$i; else break; printf "%s %d %s\n", $1, s, $NF}' >> $LOG; }
echo "=== $(date) start probe4 N=$N" >> $LOG
for i in $(seq 1 $N); do
  $D/load-rmi.sh patched >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  sleep 3
  echo "=== $(date) cycle $i: resumed; swipe the pad" >> $LOG
  irqs "before capture $i"
  $P/motw900.sh $D/probe4-$i.txt; { echo "--- probe4-$i"; cat $D/probe4-$i.txt; } >> $LOG
  irqs "after capture $i"
  if degraded $D/probe4-$i.txt; then
    TP=$(grep -l "pass-through" /sys/bus/serio/devices/serio*/description | head -1 | xargs dirname)
    echo "=== $(date) cycle $i DEGRADED -> rebind TrackPoint psmouse on $TP; swipe again" >> $LOG
    echo -n psmouse > $TP/drvctl; sleep 3
    irqs "before TPrebind capture"
    $P/motw900.sh $D/probe4-$i-afterTPrebind.txt; { echo "--- probe4-$i-afterTPrebind"; cat $D/probe4-$i-afterTPrebind.txt; } >> $LOG
    irqs "after TPrebind capture"
    if degraded $D/probe4-$i-afterTPrebind.txt; then
      echo "=== $(date) still DEGRADED -> rebind rmi4_smbus; swipe again" >> $LOG
      echo -n 11-002c > /sys/bus/i2c/drivers/rmi4_smbus/unbind; sleep 1; echo -n 11-002c > /sys/bus/i2c/drivers/rmi4_smbus/bind; sleep 3
      $P/motw900.sh $D/probe4-$i-afterRebind.txt; { echo "--- probe4-$i-afterRebind"; cat $D/probe4-$i-afterRebind.txt; } >> $LOG
    fi
    break
  fi
  sleep 5
done
echo "=== $(date) done probe4" >> $LOG
