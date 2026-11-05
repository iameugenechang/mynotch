#!/bin/bash
# Compile production adapters against controlled transports. Never launches the app.
set -euo pipefail
cd "$(dirname "$0")/.."
build=$(mktemp -d "${TMPDIR:-/tmp}/anotchup-native.XXXXXX")
trap 'rm -rf "$build"' EXIT
for module in MediaFeature CameraFeature CalendarFeature; do
  xcrun swiftc -swift-version 5 -parse-as-library -emit-library -emit-module \
    -module-name "$module" Packages/AnotchupFeatures/Sources/"$module"/*.swift \
    -emit-module-path "$build/$module.swiftmodule" -o "$build/lib$module.dylib"
done
xcrun swiftc -swift-version 5 -parse-as-library -I "$build" -L "$build" \
  -lMediaFeature -lCameraFeature -lCalendarFeature \
  anotchup/models/PlaybackState.swift anotchup/MediaControllers/MediaControllerProtocol.swift \
  anotchup/MediaControllers/AppleMusicController.swift anotchup/MediaControllers/SpotifyController.swift \
  anotchup/MediaControllers/NowPlayingController.swift \
  anotchup/MediaControllers/"YouTube Music Controller"/*.swift \
  anotchup/managers/WebcamManager.swift anotchup/Providers/CalendarServiceProviding.swift \
  anotchup/models/CalendarModel.swift anotchup/models/EventModel.swift \
  anotchup/components/Shelf/Models/Bookmark.swift anotchup/extensions/URL+SecurityScoped.swift \
  anotchup/extensions/NSItemProvider+LoadHelpers.swift \
  Tests/NativeAdapterContractTests.swift -o "$build/native-contracts"
"$build/native-contracts"
