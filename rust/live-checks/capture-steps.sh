#!/bin/bash
# No input events. Runs timed steps and captures the probe by window id after each.
# usage: capture-steps.sh <step-ms> <steps>     e.g. 2500 frame,frame,mirror,frame,resize,frame,mirror
# Then: python3 camcheck.py <steps>   (run from $OUT)
source "$(dirname "$0")/common.sh"; cd "$OUT"; rm -f cam-*.png
"$BIN" --show --steps "$2" --step-ms "$1" > "$PROBE_LOG" 2>&1 & pid=$!
for i in $(seq 50); do grep -q 'probe ready' "$PROBE_LOG" && break; sleep 0.1; done
id=$(probe_window_id); sleep 0.6; screencapture -x -o -l "$id" cam-0.png
[ "$(grep -c '^\[step\]' "$PROBE_LOG")" = 0 ] || { echo "first capture came after a step; use a longer interval" >&2; kill $pid; exit 2; }
n=0; total=$(echo "$2" | tr ',' '\n' | wc -l | tr -d ' ')
while [ $n -lt $total ] && kill -0 $pid 2>/dev/null; do
    seen=$(grep -c '^\[step\]' "$PROBE_LOG")
    if [ "$seen" -gt "$n" ]; then n=$seen; sleep 0.6; screencapture -x -o -l "$id" "cam-$n.png" 2>/dev/null; fi
    sleep 0.05
done
if kill -0 $pid 2>/dev/null; then kill $pid; wait $pid 2>/dev/null; else wait $pid; echo "probe exit=$?"; fi
# The twin logs where its video box landed; the GPUI probe uses the default.
BOX=$(sed -n 's/^\[video\] box=//p' "$PROBE_LOG" | head -1) python3 "$HERE/camcheck.py" "$2"
