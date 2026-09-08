#!/bin/bash
# usage: probe10.sh N [START] [MODE] -- MODE 1 (default): rmi_reset() before+after; MODE 2: after only (upstream move form). cycles with the in-driver cure: rmi_smbus resume_reconfig_after=1 (rmi_reset() after
# rmi_driver_resume()). After each wake: 3 s, then swipe-triggered capture. If degraded: xport_reset by hand, capture again.
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/rmi4
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
N=$1; S=${2:-1}; M=${3:-1}; T=probe10; [ "$M" != 1 ] && T=probe10-m$M; LOG=$D/$T.log; bad=0
degraded() { awk '/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2} END{exit !(d>c)}' "$1"; }
echo "=== $(date) start probe10 N=$N START=$S MODE=$M (resume_reconfig_after=$M, in-driver)" >> $LOG
for i in $(seq $S $((S+N-1))); do
  $D/load-smbus.sh resume_reconfig_after=$M >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  sleep 3
  journalctl -k --since "-30s" --no-pager 2>/dev/null | grep -E 'resume_reconfig_after|xport_reset|rmi4_smbus' | tail -3 >> $LOG
  echo "=== $(date) cycle $i: resumed; swipe the pad" >> $LOG
  $P/motw900.sh $D/$T-$i.txt; { echo "--- $T-$i"; cat $D/$T-$i.txt; } >> $LOG
  if degraded $D/$T-$i.txt; then
    bad=$((bad+1)); echo "=== cycle $i DEGRADED with in-driver reconfig ($bad/$i) -> armB by hand; swipe again" >> $LOG
    R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-* | head -1); echo 1 > $R/xport_reset; sleep 1
    $P/motw60.sh $D/$T-$i-b.txt; { echo "--- $T-$i-b"; cat $D/$T-$i-b.txt; } >> $LOG
    degraded $D/$T-$i-b.txt && echo "=== still DEGRADED after touched armB" >> $LOG || echo "=== CLEAN after touched armB" >> $LOG
  else echo "=== cycle $i clean after in-driver reconfig ($bad/$i degraded)" >> $LOG; fi
  sleep 5
done
echo "=== $(date) done probe10: $bad/$N degraded" >> $LOG
