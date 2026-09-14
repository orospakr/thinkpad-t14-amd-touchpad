#!/bin/bash
# user-side cue for probe8/probe9 runs: tail the log, play a sound + notify at each transition
# usage: cue.sh LOGFILE
S=/usr/share/sounds/freedesktop/stereo
cue() { pw-play "$S/$1" >/dev/null 2>&1 & notify-send -u critical -t "${3:-8000}" "touchpad probe" "$2" 2>/dev/null; }
tail -n0 -F "$1" | while read -r line; do
  case "$line" in
    *"suspending"*)          cue power-unplug.oga "suspending - hands off the pad" 5000 ;;
    *"DO NOT TOUCH"*)        w=$(sed -n 's/.*for \([0-9]*\) s.*/\1/p' <<<"$line"); cue dialog-warning.oga "AWAKE - hands off the pad for ${w:-60} s" $(( ${w:-60} * 1000 )) ;;
    *"swipe the pad"*)       cue complete.oga "SWIPE NOW - one finger, keep moving until the next sound" 30000 ;;
    *"clean after"*)         cue message.oga "clean - stop, hands off" ;;
    *"CLEAN after touched"*) cue message.oga "cured by touched reset - run ends" ;;
    *"DEGRADED"*"swipe again"*) cue dialog-error.oga "DEGRADED - re-armed, SWIPE AGAIN now" 30000 ;;
    *"DEGRADED after untouched"*) cue dialog-error.oga "DEGRADED - re-armed, SWIPE AGAIN now" 30000 ;;
    *"still DEGRADED"*)      cue dialog-error.oga "still degraded after touched reset - run ends" ;;
    *"reattach failed"*)     cue suspend-error.oga "re-attach FAILED - run stopped" ;;
    *"done probe"*)          cue alarm-clock-elapsed.oga "run finished" ;;
  esac
done
