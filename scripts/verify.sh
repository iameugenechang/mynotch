#!/bin/bash
# Background-only checks. Build flags compile the unsigned app without launching it.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ($# -eq 1 && "$1" != "--build" && "$1" != "--release-build") ]]; then
  echo "Usage: scripts/verify.sh [--build|--release-build]" >&2
  exit 2
fi
python3 Tests/test_boundaries.py
python3 scripts/check-boundaries.py
scripts/test-identity.sh
python3 -m unittest discover -s .github/scripts/tests
scripts/test-one-goal.sh
scripts/test-native-contracts.sh
scripts/test-optimized-geometry.sh
plutil -lint anotchup.xcodeproj/project.pbxproj
git diff --check
if [[ $# -eq 1 ]]; then
  configuration=Debug
  if [[ "$1" == "--release-build" ]]; then configuration=Release; fi
  xcodebuild -project anotchup.xcodeproj -scheme anotchup \
    -configuration "$configuration" -destination 'platform=macOS' \
    -derivedDataPath "${ANOTCHUP_BUILD_DIR:-/tmp/anotchup-build}" \
    CODE_SIGNING_ALLOWED=NO build
fi
