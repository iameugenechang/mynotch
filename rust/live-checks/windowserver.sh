#!/bin/bash
# No input events. WindowServer CPU while each variant runs a pulse, interleaved with a no-probe baseline.
# WindowServer serves the whole desktop, so this is noisy: read the spread across rounds, not one number.
# usage: windowserver.sh [rounds]
HERE="$(cd "$(dirname "$0")" && pwd)"; G="$HERE/../target/release/anotchup-gates"; T="$HERE/../target/twin-release/anotchup-twin"
ws=$(pgrep -x WindowServer); cs() { ps -o cputime= -p $1 | awk -F'[:.]' '{print ($1*60+$2)*100+$3}'; }
w() { local a=$(cs $ws); sleep 6; local b=$(cs $ws); echo "$(( (b-a)*100/600 ))"; }
run() { "$@" --show --steps pulse --step-ms 1000 >/dev/null 2>&1 & local p=$!; sleep 3; w; kill $p; wait $p 2>/dev/null; }
for round in $(seq ${1:-5}); do
    echo "round $round: none=$(w)% gpui=$(run "$G")% twin=$(run "$T")% twin_no_clip=$(TWIN_NO_CLIP=1 run "$T")% twin_plain_backdrop=$(TWIN_PLAIN_BACKDROP=1 run "$T")% seconds_since_input=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')"
done 2>/dev/null
