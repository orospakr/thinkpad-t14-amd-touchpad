#!/bin/bash
OUT=$1
n=$(grep -A5 'TM3471' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
timeout --foreground 60 evtest /dev/input/$n 2>/dev/null | grep -a --line-buffered 'SYN_REPORT' | grep --line-buffered -o 'time [0-9.]*' | awk '{print $2; fflush()}' | { read first || exit; echo "$first"; end=$(echo "$first + 20" | bc); while read t; do echo "$t"; [ "$(echo "$t > $end" | bc)" = 1 ] && break; done; } > $OUT.syn
pkill -f "evtest /dev/input/$n" 2>/dev/null
awk 'NR>1{d=int(($1-p)*1000+0.5); h[d]++; n++} {p=$1} END{print "syn_reports="n; for(k in h) print k"ms", h[k]}' $OUT.syn | sort -k1 -n | head -14 > $OUT
awk 'NR>1{printf "%d ", int(($1-p)*1000+0.5)} {p=$1} NR==80{exit}' $OUT.syn >> $OUT
