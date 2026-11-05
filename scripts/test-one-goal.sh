#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/anotchup-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
# Compile and test the same modules linked by the app. No app host or package downloads.
xcrun swift test --package-path Packages/AnotchupFeatures --scratch-path "$build_dir/package"
target="$(uname -m)-apple-macos14.0"
xcrun swiftc -parse-as-library -target "$target" \
  anotchup/models/OneGoalPresentation.swift \
  Packages/AnotchupFeatures/Sources/MediaFeature/PlaybackState.swift \
  Tests/OneGoalPresentationTests.swift \
  -o "$build_dir/OneGoalPresentationTests"
"$build_dir/OneGoalPresentationTests"
xcrun swiftc -parse-as-library -target "$target" \
  anotchup/models/OneGoalPresentation.swift \
  anotchup/components/Music/MusicVisualizer.swift \
  Tests/OneGoalRendererTests.swift \
  -o "$build_dir/OneGoalRendererTests"
"$build_dir/OneGoalRendererTests"
