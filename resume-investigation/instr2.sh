#!/bin/bash
S=$1; TAG=$2; SECS=$3
T=/sys/kernel/tracing
dmesg -C
for m in psmouse rmi_smbus rmi_core; do echo "module $m +p" > /sys/kernel/debug/dynamic_debug/control 2>/dev/null; done
echo 'module i2c_piix4 format "ASF Host Notify from" +p' > /sys/kernel/debug/dynamic_debug/control
echo > $T/trace; echo 1 > $T/events/smbus/enable; echo 1 > $T/events/power/suspend_resume/enable; echo 1 > $T/tracing_on
echo 1 > /sys/module/i8042/parameters/debug
rtcwake -m no -s $SECS >/dev/null 2>&1; systemctl suspend
sleep 20; while ! dmesg | grep -q 'suspend exit'; do sleep 1; done
sleep 10
echo 0 > /sys/module/i8042/parameters/debug
echo 0 > $T/tracing_on; echo 0 > $T/events/smbus/enable; echo 0 > $T/events/power/suspend_resume/enable
for m in psmouse rmi_smbus rmi_core; do echo "module $m -p" > /sys/kernel/debug/dynamic_debug/control 2>/dev/null; done
echo 'module i2c_piix4 format "ASF Host Notify from" -p' > /sys/kernel/debug/dynamic_debug/control
dmesg > $S/dmesg_$TAG.txt; cat $T/trace > $S/trace_$TAG.txt; chmod a+r $S/dmesg_$TAG.txt $S/trace_$TAG.txt
$S/motw.sh $S/mot_$TAG.txt
