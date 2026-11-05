#!/bin/bash
# Compile the actual shell module and a separate AppKit client with optimization.
# No windows, app instance, permissions, or external services are used.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/anotchup-optimized-geometry.XXXXXX")
trap 'rm -rf "$work"' EXIT
sdk=$(xcrun --sdk macosx --show-sdk-path)
target="$(uname -m)-apple-macosx14.0"
flags=(-swift-version 5 -O -whole-module-optimization -sdk "$sdk" -target "$target")
xcrun swiftc "${flags[@]}" -parse-as-library -emit-library -emit-module \
  -module-name NotchShell -emit-module-path "$work/NotchShell.swiftmodule" \
  Packages/AnotchupFeatures/Sources/NotchShell/*.swift \
  -o "$work/libNotchShell.dylib" \
  -Xlinker -install_name -Xlinker @rpath/libNotchShell.dylib
xcrun swiftc "${flags[@]}" -I "$work" -L "$work" -lNotchShell \
  -Xlinker -rpath -Xlinker "$work" \
  Tests/OptimizedGeometryTests.swift -o "$work/geometry-tests"
"$work/geometry-tests"
