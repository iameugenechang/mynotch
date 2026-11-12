#!/bin/bash
# No input events. Context switches per second and CPU time in fixed windows of a scripted run.
# usage: idle-phases.sh <steps> <step-ms> <label:start-seconds:length-seconds> ...
#   e.g. idle-phases.sh pulse,pulse 10000 idle-before:3:6 pulsing:12:6 idle-after:24:6
source "$(dirname "$0")/common.sh"; steps=$1; ms=$2; shift 2
"$BIN" --show --steps "$steps" --step-ms "$ms" > "$PROBE_LOG" 2>&1 & pid=$!
t0=$(date +%s)
cpu() { ps -o cputime= -p $pid | awk -F'[:.]' '{print ($1*60+$2)*100+$3}'; }
for spec in "$@"; do IFS=: read label start len <<< "$spec"
    while [ $(( $(date +%s) - t0 )) -lt $start ]; do sleep 0.2; done
    a=$(cpu); out=$(top -l 2 -s $len -pid $pid -stats pid,csw 2>/dev/null | awk -v p=$pid '$1==p {gsub(/\+/,"",$2); c[++n]=$2} END {print c[2]-c[1]}'); b=$(cpu)
    echo "$label: context_switches/s=$(( out / len )) cpu_centiseconds_per_10s=$(( (b-a) * 10 / len ))"
done
kill $pid 2>/dev/null; wait $pid 2>/dev/null; true
