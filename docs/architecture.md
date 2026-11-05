# Current architecture

The feature implementation and automated contract-test work in [the plan](architecture-plan.md) are complete. Native acceptance and release readiness are not implied.

## Dependency direction

`Packages/AnotchupFeatures` has no external dependencies. Logic targets import Foundation/Combine, with one file-scoped CoreGraphics exception for `NotchGeometry.swift`, and have no dependency on a sibling feature. The explicit geometry import avoids a [Release compiler crash](release-compiler-crash.md); it adds no native effects. Adapter targets depend on their own logic. Swift target boundaries and `scripts/check-boundaries.py` enforce this direction.

| Component | Owns | Contract |
| --- | --- | --- |
| WorkingOn | Saved goal/countdown, completion, independent editor drafts | [Working on](working-on-contract.md) |
| NotchShell | Display lifetimes, shared navigation, editor-focus policy, delayed interactions, geometry arithmetic | [Shell](notch-shell-contract.md) |
| MediaFeature | Normalized playback, provider replacement, command routing, content revisions | [Media](media-contract.md) |
| ShelfFeature | Collection transactions, import/validation lifetime, sharing completion | [Shelf](shelf-contract.md) |
| CalendarFeature | Day queries, loading/error state, stale-result rejection | [Calendar](calendar-contract.md) |
| CameraFeature | Explicit authorization requests and serialized capture intent | [Camera](camera-contract.md) |
| SystemHUD | Validated messages, activation, connection generations | [HUD](system-hud-contract.md) |
| AppIdentity | Destination-first, retryable preferences migration | [Identity](identity-migration.md) |

Package adapters implement isolated preferences, timers/tasks, notification subscriptions, and JSON storage. Native adapters remain in the app where AppKit, AVFoundation, EventKit, XPC, and player protocols are needed. They accept controlled effects or transports for tests. Native facade names and some `.shared` entry points remain for UI compatibility; feature logic does not discover collaborators through them.

## Composition and ownership

`anotchup/anotchupApp.swift` is the composition root. The bootstrap migrates preferences before SwiftUI property wrappers or app services initialize. Factories wire native adapters and cross-feature outputs. Startup and termination own service start/stop.

One Working on store and one countdown monitor serve all display trees. Each display owns its model, native window observer, and delayed interaction lifetime. Shared navigation is deliberate; drafts, focus requests, hover, and deadlines remain display-local. Reconciliation retains unchanged displays and tears down removed ones before creating replacements. The shell receives media refresh, camera commands, and feature reads as injected effects.

Cancellation has two meanings: reusable cancellation discards pending work; terminal stop/invalidation rejects new work. Tickets, content revisions, and connection generations reject callbacks that arrive after cancellation. Resource cleanup belongs to the owner that acquired the resource, not an arbitrary timeout.

## Verification

Run `scripts/verify.sh` for all background checks, `scripts/verify.sh --build` to include the unsigned Debug app build, or `scripts/verify.sh --release-build` for the unsigned Release build. Run `scripts/test-native-contracts.sh` for native adapter fixtures alone. These commands do not launch the app, request permissions, play sound, contact external players, or migrate actual user preferences.

The automated coverage includes:

- 79 public-API XCTest cases across feature logic, persistence/scheduler conformance, display/editor composition, notification delivery, and migration.
- The retained 499 behavior, contract, presentation/media, and offscreen renderer assertions/checks. The package's original aggregate cases contain part of this count; these are not 499 additional XCTest cases.
- 52 production native-adapter checks using controlled transports, real temporary bookmarks, and in-process item providers.
- An optimized, cross-module AppKit geometry consumer, which catches a compiler failure that Foundation-only package tests miss.
- Five boundary-rule and five identity Python tests, 39 workflow utility tests, Shelf directory migration/temporary-storage checks, project validation, and whitespace checks.

`scripts/verify.sh --build` passed with Xcode 27.2 (27B52), including the unsigned Debug build. Built app and embedded helper identifiers were checked as `com.iameugenechang.anotchup` and `com.iameugenechang.anotchup.AnotchupXPCHelper`. A subsequent clean Release build and full suite also passed after the explicit geometry import. An ad-hoc signed Release build passed, but signed-helper and other native runtime acceptance were not tested.

Tests use isolated preferences and temporary files. Live effect defaults fail closed in the native runner. Package tests use public imports rather than `@testable`. Fixture conformance proves translation and ownership behavior, not that a third-party service still honors its protocol.

## Acceptance and release limits

Not performed automatically:

- Physical notch/camera-cutout readability, SwiftUI focus transfer, animations, real display removal, and OS lock/unlock events.
- Real player automation, lyrics endpoint behavior, EventKit stores, camera capture, system sharing, permission dialogs, audio, or login-item registration.
- Signed XPC helper resolution, privileged authorization, and event-tap behavior.

The MediaRemoteAdapter binary still targets macOS 15 while the app declares macOS 14. Do not claim macOS 14 runtime support from a successful build. Swift 5 builds also retain native concurrency/deprecation warnings; this work is not a Swift 6 migration.

Distribution still needs a separate signing/notarization and license/asset/dependency audit, bundled notices, and corresponding-source delivery. Upstream publishing workflows and updater feeds remain inactive historical material, not fork release infrastructure. No release was published or repository renamed.
