#!/bin/bash
# usage: probe5.sh N -- on a degraded wake try arms in order: B xport_reset, A reconfig, D hwreset+B+A, then full rebind
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/rmi4
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
N=$1; LOG=$D/probe5.log
degraded() { awk '/^1[23]ms/{d+=$2} /^1[45]ms/{c+=$2} END{exit !(d>c)}' "$1"; }
alive() { grep -q '^syn_reports=[1-9]' "$1"; }
dev() { ls -d /sys/bus/i2c/devices/11-002c/rmi4-* | head -1; }
cap() { echo "=== $(date) $1: swipe the pad" >> $LOG; $P/motw60.sh $D/probe5-$1.txt; { echo "--- probe5-$1"; cat $D/probe5-$1.txt 2>/dev/null; } >> $LOG; }
arm() { # name cmd...
  name=$1; shift; echo "=== $(date) arm $name: $*" >> $LOG; eval "$@"; sleep 2
  cap "$name"
  if ! alive $D/probe5-$name.txt; then echo "=== pad DEAF after $name" >> $LOG; return 2; fi
  if degraded $D/probe5-$name.txt; then echo "=== still DEGRADED after $name" >> $LOG; return 1; fi
  echo "=== CLEAN after $name" >> $LOG; return 0
}
echo "=== $(date) start probe5 N=$N" >> $LOG
for i in $(seq 1 $N); do
  $D/load-rmi.sh patched >> $LOG 2>&1 || { echo "!!! reattach failed" >> $LOG; break; }
  s0=$(cat /sys/power/suspend_stats/success)
  echo "=== $(date) cycle $i: suspending" >> $LOG
  rtcwake -m no -s 90 >/dev/null; systemctl suspend
  while [ "$(cat /sys/power/suspend_stats/success)" = "$s0" ]; do sleep 1; done
  sleep 3
  echo "=== $(date) cycle $i: resumed; swipe the pad" >> $LOG
  $P/motw900.sh $D/probe5-$i.txt; { echo "--- probe5-$i"; cat $D/probe5-$i.txt; } >> $LOG
  if degraded $D/probe5-$i.txt; then
    echo "=== $(date) cycle $i DEGRADED" >> $LOG
    R=$(dev)
    arm B-xport_reset "echo 1 > $R/xport_reset"; rc=$?
    [ $rc = 1 ] && { arm A-reconfig "echo 1 > $R/reconfig"; rc=$?; }
    [ $rc = 1 ] && { arm D-hwreset "echo 1 > $R/hwreset; echo 1 > $R/xport_reset; echo 1 > $R/reconfig"; rc=$?; }
    [ $rc != 0 ] && { arm Z-rebind "echo -n 11-002c > /sys/bus/i2c/drivers/rmi4_smbus/unbind; sleep 1; echo -n 11-002c > /sys/bus/i2c/drivers/rmi4_smbus/bind; sleep 3"; }
    journalctl -k -b --since "-10min" --no-pager | grep -i "rmi4" | tail -15 | cut -c17-140 >> $LOG
    break
  fi
  sleep 5
done
echo "=== $(date) done probe5" >> $LOG
