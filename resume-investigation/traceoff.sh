#!/bin/bash
pkill -f "scratchpad/ins""tr.sh" 2>/dev/null
for m in psmouse rmi_smbus rmi_core; do echo "module $m -p" > /sys/kernel/debug/dynamic_debug/control; done
echo 'module i2c_piix4 format "Transaction (pre)" -p' > /sys/kernel/debug/dynamic_debug/control
echo 'module i2c_piix4 format "ASF Host Notify from" -p' > /sys/kernel/debug/dynamic_debug/control
echo 0 > /sys/module/i8042/parameters/debug
echo "i8042.debug=$(cat /sys/module/i8042/parameters/debug) dyndbg_on=$(grep -cE '\] .*=p' /sys/kernel/debug/dynamic_debug/control) dmesg_lines=$(dmesg | wc -l)"
