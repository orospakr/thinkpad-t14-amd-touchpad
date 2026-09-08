#!/bin/bash
# 20 s raw capture of the pad's MT events + libinput verbose log; usage: pressure-capture.sh OUTPREFIX
n=$(grep -A5 'TM3471' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
snap() { awk '/^ *[0-9]+:/{n=$1; s=0; for(i=2;i<=NF;i++){ if($i ~ /^[0-9]+$/) s+=$i; else break}; lab=""; for(j=i;j<=NF;j++) lab=lab" "$j; if(lab ~ /piix4-asf|rmi4_smbus|fn12|fn03/) printf "%s%s ", n, s}' /proc/interrupts; echo; }
I0=$(snap)
timeout --foreground ${DUR:-20} stdbuf -o0 libinput debug-events --verbose --enable-tap --device /dev/input/$n > $1.libinput 2>&1 &
timeout --foreground ${DUR:-20} stdbuf -o0 evtest /dev/input/$n 2>&1 | grep -aE 'ABS_MT_SLOT|ABS_MT_POSITION|ABS_MT_PRESSURE|ABS_MT_TOOL_TYPE|ABS_MT_TRACKING_ID|ABS_MT_TOUCH_MAJOR|BTN_TOOL|BTN_LEFT|SYN_REPORT' > $1.evtest
wait
I1=$(snap)
echo "interrupt deltas (7=ASF hard irq, 95=host notify->rmi, 99=fn12 frames, 102=fn03):"; echo "$I0 $I1" | awk '{n=NF/2; for(i=1;i<=n;i++){split($i,x,":"); split($(i+n),y,":"); printf "  irq %s: +%d\n", x[1], y[2]-x[2]}}'
echo "evtest frames (SYN_REPORT): $(grep -ac SYN_REPORT $1.evtest); touches: $(grep -ac 'TRACKING_ID), value [0-9]' $1.evtest)"
echo "pressure histogram (all MT_PRESSURE samples):"; grep -a 'ABS_MT_PRESSURE' $1.evtest | awk '{print $NF}' | awk '{b=int($1/10)*10; h[b]++; n++} END{for(k in h) printf "%3d-%3d %5d\n", k, k+9, h[k]; print "samples", n}' | sort -n
echo "tool types:"; grep -a 'ABS_MT_TOOL_TYPE' $1.evtest | awk '{print $NF}' | sort | uniq -c
echo "libinput thumb/tap/gesture lines:"; grep -aiE 'thumb|tap:|gesture|pinch|palm' $1.libinput | cut -c1-120 | sort | uniq -c | sort -rn | head -25
