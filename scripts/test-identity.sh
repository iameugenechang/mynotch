#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Tests/test_identity.py
scratch=$(mktemp -d "${TMPDIR:-/tmp}/anotchup-identity.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc anotchup/components/Shelf/Services/ShelfStorageLocation.swift \
  Tests/ShelfStorageLocationTests.swift -o "$scratch/shelf-migration-tests"
"$scratch/shelf-migration-tests"
xcrun swiftc anotchup/components/Shelf/Services/TemporaryFileStorageService.swift \
  Tests/ShelfTemporaryStorageTests.swift -o "$scratch/shelf-temporary-tests"
"$scratch/shelf-temporary-tests"
