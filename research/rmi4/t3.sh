#!/bin/bash
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/rmi4
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/psmouse
LOG=$D/t3.log
R=$(ls -d /sys/bus/i2c/devices/11-002c/rmi4-* | head -1)
TP=$(grep -l "pass-through" /sys/bus/serio/devices/serio*/description | head -1 | xargs dirname)
cap() { echo "=== $(date) $1: swipe the pad" >> $LOG; $P/motw60.sh $D/t3-$1.txt; { echo "--- t3-$1"; head -8 $D/t3-$1.txt; } >> $LOG; }
echo "=== $(date) start t3 R=$R TP=$TP" >> $LOG
echo 1 > $R/xport_reset; sleep 1
cap 1-after-armB
echo "=== $(date) TrackPoint reconnect via $TP/drvctl" >> $LOG
echo -n reconnect > $TP/drvctl; sleep 3
cap 2-after-TPreconnect
echo 1 > $R/xport_reset; sleep 1
cap 3-after-armB-again
journalctl -k -b --since "-5min" --no-pager | grep -i "rmi4\|psmouse\|trackpoint" | tail -8 | cut -c17-140 >> $LOG
echo "=== $(date) done t3" >> $LOG
