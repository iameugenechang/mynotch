#!/bin/bash
# Background-only checks. --build also compiles the unsigned app, without launching it.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ($# -eq 1 && "$1" != "--build") ]]; then
  echo "Usage: scripts/verify.sh [--build]" >&2
  exit 2
fi
python3 Tests/test_boundaries.py
python3 scripts/check-boundaries.py
scripts/test-identity.sh
python3 -m unittest discover -s .github/scripts/tests
scripts/test-one-goal.sh
plutil -lint anotchup.xcodeproj/project.pbxproj
git diff --check
if [[ "${1:-}" == "--build" ]]; then
  xcodebuild -project anotchup.xcodeproj -scheme anotchup \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "${ANOTCHUP_BUILD_DIR:-/tmp/anotchup-build}" \
    CODE_SIGNING_ALLOWED=NO build
fi
