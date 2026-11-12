#!/bin/bash
# TAKES OVER THE POINTER AND KEYBOARD. Starts a fresh probe and runs scratch ops against it.
# usage: input-session.sh <op> ...   Ops: sclick clear pclick:x:y pmove:x:y key:<keycode> wait:<ms>
#        shot:<name> region:<name> strip:<name> full top space:left|right mission place:x:y click:x:y prclick:x:y pscroll:x:y pburst:x:y:count pglide:x:y:screenx:screeny frame
#        type:<a-z, 1-3, _ for space> mkey:<keycode>:<c|s|o modifiers> ukey:<unicode text> pdbl:x:y
# mkey saves the whole pasteboard first; it is restored when the session ends.
# PROBE_ARGS adds probe flags, e.g. PROBE_ARGS="--steps frame --step-ms 12000".
# State lines include downs, the mouse-down count seen by the scratch app, for click-through checks.
# Probe points at 560x320: begin 120:63, end 218:63, quit 290:63, text field 150:97, frame 64:283,
# mirror 148:283, resize 217:283 (235:283 once mirrored), remove 345:283.
source "$(dirname "$0")/common.sh"
clang -fobjc-arc -framework AppKit -o "$OUT/scratch" "$HERE/scratch.m" || exit 2
pkill -x anotchup-gates; sleep 0.3
"$BIN" --show $PROBE_ARGS > "$PROBE_LOG" 2>&1 &
for i in $(seq 50); do grep -q 'probe ready' "$PROBE_LOG" && break; sleep 0.1; done
"$OUT/scratch" "$@"
pkill -x anotchup-gates; true
