#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/anotchup-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
target="$(uname -m)-apple-macos14.0"
xcrun swiftc -parse-as-library -target "$target" \
  boringNotch/models/OneGoal.swift \
  boringNotch/models/OneGoalStore.swift \
  boringNotch/models/OneGoalDependencies.swift \
  boringNotch/helpers/OneGoalAdapters.swift \
  boringNotch/models/PlaybackState.swift \
  Tests/OneGoalTests.swift \
  -o "$build_dir/OneGoalTests"
"$build_dir/OneGoalTests"
xcrun swiftc -parse-as-library -target "$target" \
  boringNotch/models/OneGoal.swift \
  boringNotch/models/OneGoalStore.swift \
  boringNotch/models/OneGoalDependencies.swift \
  boringNotch/helpers/OneGoalAdapters.swift \
  Tests/OneGoalContractTests.swift \
  -o "$build_dir/OneGoalContractTests"
"$build_dir/OneGoalContractTests"
xcrun swiftc -parse-as-library -target "$target" \
  boringNotch/models/OneGoal.swift \
  boringNotch/components/Music/MusicVisualizer.swift \
  Tests/OneGoalRendererTests.swift \
  -o "$build_dir/OneGoalRendererTests"
"$build_dir/OneGoalRendererTests"
