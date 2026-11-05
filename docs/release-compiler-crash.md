# Release geometry compiler crash

## Reproduction

Observed with Xcode 27.2 (27B52), Apple Swift 6.4.2 (`swiftlang-6.4.2.1.9`), macOS SDK 27.2, arm64, Swift language mode 5. The compiler reports effective language version 5.10. A Release app build crashed with signal 11 in `PerformanceSILLinker` while deserializing `NotchGeometry.origin(screen:window:)` from `NotchShell`.

The app, SwiftUI, external packages, signing, and native services are not needed to reproduce it:

```bash
work=$(mktemp -d)
cd "$work"

cat > Geometry.swift <<'SWIFT'
import Foundation
public func makePoint(_ x: Double) -> CGPoint { CGPoint(x: x, y: 0) }
SWIFT

cat > Client.swift <<'SWIFT'
import AppKit
import Geometry
let point = makePoint(3)
precondition(point.x == 3 && point.y == 0)
SWIFT

xcrun swiftc -swift-version 5 -O -whole-module-optimization \
  -parse-as-library -emit-library -emit-module -module-name Geometry \
  Geometry.swift -o "$work/libGeometry.dylib"
xcrun swiftc -swift-version 5 -O -whole-module-optimization \
  -I "$work" -L "$work" -lGeometry Client.swift -o client
```

On this toolchain the second command crashes. It is an import-sensitive optimized SIL deserialization failure. The exact compiler/SDK implementation defect has not been diagnosed, and no upstream bug report has been filed.

Controlled variations on the same toolchain:

- Foundation-only library plus optimized AppKit or CoreGraphics client: compiler crash.
- Foundation-only library plus optimized Foundation-only client: builds and runs.
- Foundation-only library plus unoptimized AppKit client: builds and runs.
- Library explicitly importing CoreGraphics, with or without Foundation, plus optimized AppKit client: builds and runs.

The regression client also reproduces the crash against the original production `NotchShell` sources at commit `301a288`. This rules out an issue confined to the reduced example or stale Xcode build products.

## Fix

`NotchGeometry` now lives in its own source file with an explicit `import CoreGraphics`. Its public geometry types and arithmetic are unchanged. No optimization flags, deployment targets, or compiler-version settings were changed. No underscored compiler attributes are used.

The boundary checker allows CoreGraphics only in `Sources/NotchShell/NotchGeometry.swift`. Other logic files remain Foundation/Combine-only, and AppKit/SwiftUI imports remain forbidden throughout logic. Geometry uses value types, not native windows or services.

`scripts/test-optimized-geometry.sh` compiles the actual `NotchShell` source as an optimized module, then compiles and runs a separate optimized AppKit consumer. Package-only tests did not catch this import combination. The check runs in the normal `scripts/verify.sh` suite and creates no app instance or windows.

## Verification

- Optimized cross-module regression: failed with original production sources, passed after the explicit import.
- Ad-hoc signed Release app build: passed with optimizations enabled.
- Clean Release app build plus full verification: passed using `scripts/verify.sh --release-build`, including 79 XCTest cases, 52 native-adapter checks, existing behavior/presentation/renderer checks, five boundary and five identity Python cases, workflow and storage checks.
- All 79 package XCTest cases also passed with SwiftPM's Release configuration; the Debug app build passed after the fix.
- The installed Debug app was not replaced or relaunched during this investigation.

Use `scripts/verify.sh --build` for the unsigned Debug build or `scripts/verify.sh --release-build` for the unsigned Release build. Successful compilation is not signed-helper or native runtime acceptance. The existing macOS 14 deployment target versus macOS 15 MediaRemoteAdapter binary mismatch remains unresolved.
