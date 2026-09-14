#!/bin/bash
# usage: load-rmi.sh stock|patched [rmi_core params]  -> swaps rmi_core, re-attaches rmi_smbus + psmouse
D=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne/research/rmi4
KO=$D/$1/rmi_core.ko; shift
for try in 1 2 3; do
  modprobe -r psmouse 2>/dev/null; rmmod rmi_smbus 2>/dev/null
  for i in $(seq 30); do ls /sys/bus/i2c/devices | grep -q '^11-' || break; sleep 0.2; done
  rmmod rmi_core 2>/dev/null; insmod $KO "$@" || modprobe rmi_core
  modprobe rmi_smbus; modprobe psmouse synaptics_intertouch=1
  sleep 2
  if grep Name= /proc/bus/input/devices | grep -q TM3471; then echo "OK rmi_core=$1 $* try=$try"; exit 0; fi
  echo "retry $try"; sleep 2
done
echo FAIL; exit 1
