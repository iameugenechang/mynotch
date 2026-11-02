#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/mynotch-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -parse-as-library \
  boringNotch/models/OneGoal.swift \
  boringNotch/models/OneGoalStore.swift \
  Tests/OneGoalTests.swift \
  -o "$build_dir/OneGoalTests"
"$build_dir/OneGoalTests"
