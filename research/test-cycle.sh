#!/bin/bash
# Load a build of the ASF-patched i2c-piix4, attach RMI4, then measure.
# Usage: sudo ./test-cycle.sh [load <path.ko>] [measure] [status]
#   load     - swap in the given module (default: module/i2c-piix4.ko)
#   measure  - 5 s touchpad motion capture: interval stats + error count
#   status   - IRQ 7 line, input names, last ASF/rmi4 dmesg lines
# Combine freely: sudo ./test-cycle.sh load module/i2c-piix4.ko measure
set -u
DIR=$(cd "$(dirname "$0")" && pwd)

do_load() {
	local ko=${1:-$DIR/module/i2c-piix4.ko}
	echo "== load $ko"
	dmesg -C
	modprobe -r psmouse
	rmmod rmi_smbus i2c_piix4 2>/dev/null
	insmod "$ko" || { echo "insmod failed"; return 1; }
	modprobe rmi_smbus
	modprobe psmouse synaptics_intertouch=1
	sleep 3
	dmesg | grep -E "ASF|rmi4_f01|input: " | sed 's/^/  /'
	if grep -q TM3471 /proc/bus/input/devices; then
		echo "  attached: yes"
	else
		echo "  attached: NO"
		return 1
	fi
}

do_measure() {
	local n
	n=$(grep -A5 'TM3471' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1)
	echo "== measure ($n): move one finger continuously for 5 s"
	timeout 5 libinput debug-events --device /dev/input/"$n" 2>/dev/null |
	grep POINTER_MOTION | grep -o '+[0-9.]*s' | tr -d '+s' |
	awk 'NR>1{d=($1-p)*1000; s+=d; n++; a[n]=d} {p=$1}
	     END{ if (!n) { print "  no motion events"; exit }
	          asort(a); printf "  events=%d mean=%.1fms median=%.1fms p90=%.1fms max=%.1fms\n",
	          n, s/n, a[int(n/2)], a[int(n*0.9)], a[n]}'
	echo "  errors: $(dmesg | grep -c 'Failed to read object data')"
}

do_status() {
	echo "== status"
	grep -E "^ *7:" /proc/interrupts | sed 's/^/  /'
	grep Name= /proc/bus/input/devices | grep -iE "TM3471|TrackPoint" | sed 's/^/  /'
	dmesg | grep -iE "ASF|rmi4" | tail -4 | sed 's/^/  /'
	dmesg | grep -E "PM: suspend (entry|exit)" | tail -2 | sed 's/^/  /'
}

[ $# -eq 0 ] && set -- status
while [ $# -gt 0 ]; do
	case $1 in
	load) shift; if [ $# -gt 0 ] && [ "${1#-}" = "$1" ] && [ -f "$1" ]; then do_load "$1"; shift; else do_load; fi ;;
	measure) do_measure; shift ;;
	status) do_status; shift ;;
	*) echo "unknown: $1"; exit 2 ;;
	esac
done
