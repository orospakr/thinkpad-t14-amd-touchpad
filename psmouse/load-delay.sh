#!/bin/bash
# re-attach with psmouse/delay build; $1 = reset delay ms. Leaves the currently loaded rmi_core alone.
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
for try in 1 2 3; do
  modprobe -r psmouse 2>/dev/null; rmmod rmi_smbus 2>/dev/null
  for i in $(seq 30); do ls /sys/bus/i2c/devices | grep -q '^11-' || break; sleep 0.2; done
  modprobe rmi_smbus; insmod $P/delay/psmouse.ko synaptics_intertouch=1 synaptics_smbus_reset_delay=$1
  sleep 2
  if grep Name= /proc/bus/input/devices | grep -q TM3471; then echo "OK delay=$1 try=$try"; exit 0; fi
  echo "retry $try"; sleep 2
done
echo FAIL; exit 1
