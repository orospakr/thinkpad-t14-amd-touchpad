#!/bin/bash
# usage: load.sh stock|patched  -> re-attaches psmouse (out-of-tree) + rmi_smbus, retries on -EEXIST
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/psmouse
KO=$P/$1/psmouse.ko
for try in 1 2 3; do
  modprobe -r psmouse 2>/dev/null; rmmod rmi_smbus 2>/dev/null
  for i in $(seq 30); do ls /sys/bus/i2c/devices | grep -q '^11-' || break; sleep 0.2; done
  modprobe rmi_smbus; modprobe psmouse synaptics_intertouch=1
  sleep 2
  if grep Name= /proc/bus/input/devices | grep -q TM3471; then echo "OK $1 try=$try"; exit 0; fi
  echo "retry $try"; sleep 2
done
echo FAIL; exit 1
