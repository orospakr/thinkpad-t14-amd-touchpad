#!/bin/bash
# doze/load-all.sh [rmi_core params] : replace the whole experimental stack (rmi_core + rmi_smbus + psmouse) from the repo builds (root)
B=/home/andrew/Work/tries/2026-08-20-thinkpad-t14-trackpad-piix4-asf-amd-cezanne
for try in 1 2 3; do
  modprobe -r psmouse 2>/dev/null; rmmod rmi_smbus 2>/dev/null
  for i in $(seq 30); do ls /sys/bus/i2c/devices | grep -q '^11-' || break; sleep 0.2; done
  rmmod rmi_core 2>/dev/null; insmod $B/rmi4/patched/rmi_core.ko "$@" || { echo "rmi_core insmod failed"; modprobe rmi_core; }
  insmod $B/rmi4/smbus/rmi_smbus.ko resume_reconfig_after=0 resume_reset_delay_ms=300
  insmod $B/psmouse/nosleep/psmouse.ko synaptics_intertouch=1 synaptics_rmi_nosleep=0 synaptics_rmi_doze_interval=6 psmouse_smbus_resume_getid=0
  sleep 2
  if grep Name= /proc/bus/input/devices | grep -q TM3471; then echo "OK load-all $* try=$try; rmi_core $(modinfo -F srcversion $B/rmi4/patched/rmi_core.ko) loaded=$(cat /sys/module/rmi_core/srcversion)"; exit 0; fi
  echo "retry $try"; sleep 2
done
echo FAIL; exit 1
