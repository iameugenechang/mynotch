# anotchup

A personal macOS notch app that keeps what you're working on in view, alongside media controls, a file Shelf, calendar, camera, and system HUD features.

anotchup is an independently maintained fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch). It is not affiliated with its maintainers. The repository currently remains at [iameugenechang/mynotch](https://github.com/iameugenechang/mynotch).

## Working on

- The caption shares the notch's width and outer curves, including media extensions. Nothing extra is shown when empty.
- Adjust font, padding, and vertical offset in Settings > Working on. The default font is 7pt.
- Choose a countdown underline or a fixed-size ring around the visualizer. Both use the existing Player tinting setting.
- Click the caption to edit. With nothing saved, open Working on beside Shelf or from the notch's right-click menu.
- Use 15/25/50-minute presets or a custom duration from one second to 24 hours. Pause, resume, restart, or clear the timer.
- Choose a completion sound and volume, or Silent. Expiry never marks your work done.
- Done clears the text and countdown, including saved state. No history is kept.
- Right-click the notch to open Settings or quit anotchup.

## Build

Build with Xcode using the `anotchup` scheme, or:

```bash
xcodebuild -project anotchup.xcodeproj -scheme anotchup \
  -configuration Debug -derivedDataPath /tmp/anotchup-build \
  CODE_SIGNING_ALLOWED=NO build
```

To launch the built app manually:

```bash
open /tmp/anotchup-build/Build/Products/Debug/anotchup.app
```

The app builds as `anotchup.app`, with bundle identifier `com.iameugenechang.anotchup`. Existing fork preferences migrate before app construction without deleting the old domain. See [identity migration](docs/identity-migration.md), including permissions that macOS may require again. Upstream auto-updates stay disabled.

The project, source paths, app-owned types, and XPC helper now use anotchup names. Shelf storage copies to the new path without deleting the original. See the [rename contract](docs/rename-contract.md) for compatibility exceptions and the [architecture plan](docs/architecture-plan.md) for implementation history. Inherited publishing workflows are disabled, not configured for fork releases.

## Checks

Run `scripts/verify.sh` for component, adapter-contract, boundary, identity/migration, workflow, layout, and offscreen renderer checks. Add `--build` for the unsigned Debug app build or `--release-build` for Release. The default checks include an optimized cross-module geometry regression test. Checks use isolated preferences, do not launch the app, and never send input, change app focus, or play sounds.

Feature logic and dependency-free adapters live in `Packages/AnotchupFeatures`. Run their public-API tests with `xcrun swift test --package-path Packages/AnotchupFeatures`. `scripts/test-native-contracts.sh` tests production media, calendar, camera, bookmark, and item-provider adapters with controlled transports and temporary fixtures. Native rendering stays outside the package.

Verified locally with Xcode 27.2 (27B52) and Python 3 on macOS. See [current architecture](docs/architecture.md) for the dependency map, component contracts, test coverage, and acceptance limits.

See [Working on implementation and manual checks](docs/one-goal.md). Physical readability and interactive window behavior still require manual acceptance checks.

## Attribution and license

This fork builds on boring.notch and its contributors' work. Original source credits remain in the code. See [LICENSE](LICENSE) and [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for license terms and dependency notices.

Projects used by the app include [MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter), [NotchDrop](https://github.com/Lakr233/NotchDrop), Calendr, and DynamicNotchKit. Original icon credit goes to [@maxtron95](https://github.com/maxtron95); the upstream website credits [@himanshhhhuv](https://github.com/himanshhhhuv).

Upstream downloads, Homebrew packages, community links, and release announcements describe boring.notch, not anotchup.
