#!/bin/bash
# usage: load-exp.sh VARIANT [psmouse params...] -> re-attach with psmouse/VARIANT/psmouse.ko and the experimental
# rmi4/smbus/rmi_smbus.ko (resume_reconfig_after=1 kept on). Retries the -EEXIST race.
P=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/psmouse
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/rmi4
V=$1; shift
for try in 1 2 3; do
  modprobe -r psmouse 2>/dev/null; rmmod rmi_smbus 2>/dev/null
  for i in $(seq 30); do ls /sys/bus/i2c/devices | grep -q '^11-' || break; sleep 0.2; done
  insmod $D/smbus/rmi_smbus.ko resume_reconfig_after=1; insmod $P/$V/psmouse.ko synaptics_intertouch=1 "$@"
  sleep 2
  if grep Name= /proc/bus/input/devices | grep -q TM3471; then echo "OK psmouse/$V $* try=$try"; exit 0; fi
  echo "retry $try"; sleep 2
done
echo FAIL; exit 1
