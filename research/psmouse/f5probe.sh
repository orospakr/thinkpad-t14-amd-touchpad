#!/bin/bash
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/psmouse
i0=$(awk '/^ *7:/{s=0; for(i=2;i<=NF;i++) if($i~/^[0-9]+$/) s+=$i; print s}' /proc/interrupts)
python3 $P/ps2cmd.py F5; sleep 1
echo "swipe now (8 s)"; sleep 8
i1=$(awk '/^ *7:/{s=0; for(i=2;i<=NF;i++) if($i~/^[0-9]+$/) s+=$i; print s}' /proc/interrupts)
echo "irq7 delta=$((i1-i0))"
journalctl -k -b --since "-20s" --no-pager | grep -i "rmi\|psmouse" | tail -3 | cut -c17-140
