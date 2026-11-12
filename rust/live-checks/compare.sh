#!/bin/bash
# No input events. Measures one app (APP=gpui or APP=twin) in separate runs: launch, idle, pulse, frame replacement.
# usage: APP=twin PROFILE=release compare.sh
source "$(dirname "$0")/common.sh"
now() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time*1000'; }
cpu() { ps -o cputime= -p $1 | awk -F'[:.]' '{print ($1*60+$2)*100+$3}'; }
fp() { footprint -p $1 2>/dev/null | awk '/phys_footprint:/ {print $2 $3; exit}'; }
ready() { for i in $(seq 100); do grep -q 'probe ready' "$PROBE_LOG" && return; sleep 0.02; done; }
# measure <pid> <seconds>: context switches per second, CPU centiseconds per 10 s, top's power score
measure() { local a=$(cpu $1) out; out=$(top -l 2 -s $2 -pid $1 -stats pid,csw,power 2>/dev/null | awk -v p=$1 '$1==p {gsub(/\+/,"",$2); c[++n]=$2; w=$3} END {print c[2]-c[1], w}'); local b=$(cpu $1)
    set -- $out $2 $a $b; echo "context_switches/s=$(( $1 / $3 )) cpu_cs_per_10s=$(( ($5 - $4) * 10 / $3 )) power=$2"; }
echo "$APP $PROFILE binary_bytes=$(stat -f %z "$BIN")"
times=(); for n in 1 2 3 4 5; do : > "$PROBE_LOG"; t0=$(now); "$BIN" --show > "$PROBE_LOG" 2>&1 & pid=$!; ready; times+=($(( $(now) - t0 ))); kill $pid; wait $pid 2>/dev/null; sleep 0.3; done
echo "launch_to_ready_ms: ${times[*]} (median $(printf '%s\n' "${times[@]}" | sort -n | sed -n 3p))"
"$BIN" --show > "$PROBE_LOG" 2>&1 & pid=$!; sleep 6
echo "idle: $(measure $pid 10) footprint=$(fp $pid)"; kill $pid; wait $pid 2>/dev/null
"$BIN" --show --steps pulse --step-ms 1000 > "$PROBE_LOG" 2>&1 & pid=$!; sleep 4
echo "pulse_animation: $(measure $pid 10) footprint=$(fp $pid)"; kill $pid; wait $pid 2>/dev/null
steps=$(python3 -c "print(','.join(['frame']*420))")
"$BIN" --show --steps "$steps" --step-ms 50 > "$PROBE_LOG" 2>&1 & pid=$!; sleep 4
echo "frames_20_per_s: $(measure $pid 10) footprint=$(fp $pid) frames_so_far=$(grep -c '^\[step\]' "$PROBE_LOG")"
sleep 12; echo "after_frames: frames=$(grep -c '^\[step\]' "$PROBE_LOG") footprint=$(fp $pid) $(measure $pid 5)"; kill $pid; wait $pid 2>/dev/null; true
