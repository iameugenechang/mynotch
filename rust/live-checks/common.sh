# Shared by the live checks. Source it; do not run it.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${PROFILE:-debug}"
BIN="$HERE/../target/$PROFILE/anotchup-gates"
export OUT="${OUT:-/tmp/anotchup-live-checks}"
export PROBE_LOG="$OUT/probe.log"
mkdir -p "$OUT"
[ -x "$BIN" ] || { echo "build first: cargo build --locked --features gui${PROFILE:+ (profile $PROFILE)}" >&2; exit 2; }
# The probe prints its window number, so no window-list query or extra permission is needed.
probe_window_id() { sed -n 's/^\[placement\] window=\([0-9]*\) .*/\1/p' "$PROBE_LOG" | head -1; }
