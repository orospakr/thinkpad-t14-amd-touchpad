#!/bin/bash
# doze/watch.sh LOG : user-side cue watcher for gcap/seq logs (notify-send + sound); exits on done/GONE/ABORT/GAVE UP
LOG=$1; i=0; until [ -f $LOG ] || [ $i -ge 10 ]; do sleep 1; i=$((i+1)); done
tail -n +1 -F $LOG 2>/dev/null | while read -r line; do case "$line" in
  *suspending*) notify-send -t 8000 "Suspending for a short cycle" "hands off the pad until the next cue"; pw-play /usr/share/sounds/freedesktop/stereo/dialog-information.oga 2>/dev/null ;;
  CAPTURE*) notify-send -t 30000 "Pad capture: ${line#CAPTURE } (30 s, starts in 4 s)" "6 slow single-finger touch-and-drags, lift fully between them, start moving right after landing."; pw-play /usr/share/sounds/freedesktop/stereo/message.oga 2>/dev/null ;;
  *GONE*|*ABORT*|"GAVE UP"*|"done "*) notify-send "Finished: $line"; pw-play /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null; pkill -P $$ tail; break ;;
esac; done
