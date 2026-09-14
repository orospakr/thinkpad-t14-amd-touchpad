#!/bin/bash
# doze/gcap.sh OUT LOG [DUR] : gated drag capture — repeats diag.sh (with a CAPTURE cue line in LOG) until >=100 frames, max 8 tries (root)
OUT=$1; LOG=$2; DUR=${3:-30}; D=$(dirname "$0")
for try in $(seq 8); do
  echo "CAPTURE $(basename $OUT) try $try" >> $LOG; sleep 4
  $D/diag.sh $OUT $DUR
  f=$(grep -c SYN_REPORT $OUT.evtest); echo "$(basename $OUT) try $try: $f frames" >> $LOG
  [ "$f" -ge 100 ] && exit 0
done
echo "GAVE UP $(basename $OUT)" >> $LOG; exit 1
