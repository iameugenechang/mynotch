# anotchup architecture and implementation plan

## Goal and scope

Make this an independently maintained app with components an agent can change and verify without launching the UI or understanding the whole codebase. The product name is `anotchup`. This is a fork of boring.notch, not a project run by its maintainers.

Preserve current behavior while changing boundaries. No new features, plugin framework, wholesale state-management framework, or automatic upstream integration. Preserve license notices and source attribution. Do not rename the remote repository or invent download URLs.

This document is the implementation backlog. Only checked items are complete. Each step should leave a buildable app; do not implement the entire plan in one patch.

## Decisions

- Organize around feature ownership, not generic models/views/managers folders.
- Use a composition root to construct dependencies and own app-wide service lifetimes. Features cannot discover collaborators through global singletons.
- Keep feature state read-only to consumers. Public commands express intent; explicit outputs request cross-component effects.
- Keep deterministic decisions separate from macOS effects. Inject clocks, scheduling, persistence, and platform access only where needed. Do not create a protocol for every class.
- Prefer value types for snapshots, commands, and events. UI-facing mutable state is main-actor isolated; asynchronous adapters document delivery and cancellation.
- Preserve current multi-display behavior initially, including shared tab selection. Separate that shared navigation from display-local hover, geometry, expansion, and editor focus ownership.
- Use a local Swift package with target-level dependency rules once the first feature is extracted. Keep AppKit/SwiftUI rendering and platform adapters in separate targets from feature logic. Avoid a package per feature and a large catch-all core module.
- Mechanical naming changes, behavioral refactors, and persisted-data migrations are separate patches.

## Intended boundaries

### App composition

Creates services, wires feature outputs to effects, and owns startup/shutdown. One shared Working on component and one completion monitor serve all display sessions. Constructing a view must not start a permission request or unrelated service.

### Notch shell

Owns display sessions, expansion, hover/drag policy, preview arbitration, and layout composition. Shared navigation and editor-focus transfer have explicit owners. The shell consumes feature snapshots and sends commands; it does not persist feature data or call media providers directly.

### Feature components

- Working on: saved text/countdown, timer transitions, and completion policy. An editor session owns its uncommitted draft separately.
- Media: active provider selection, normalized playback state, capabilities, and playback commands. Artwork/lyrics work cannot overwrite a newer track or provider.
- Shelf: item collection, selection, and item actions. File access, bookmarks, persistence, and sharing are adapters.
- Calendar: permission-aware queries and event/reminder state. EventKit types stay at the adapter boundary where practical.
- Camera and system HUD: explicit permission and service lifetimes rather than side effects of notch state construction.

A feature may supply SwiftUI views, but its behavior must be testable without creating a window. Features do not import each other's implementations. Cross-feature coordination belongs in app composition or a narrowly defined shell contract.

### macOS adapters

Implement persistence, scheduling, sound, windows/displays, media transports, EventKit, camera, permissions, and XPC. Each adapter declares resource ownership and failure behavior. Use a dependency map to prevent platform imports from leaking into feature logic.

## Contract test design

For each boundary, write a short contract beside its tests: inputs, outputs, state owner, lifetime, execution context, ordering, cancellation, errors, and compatibility guarantees. Tests assert public behavior rather than private helper calls or exact internal object graphs.

Use three layers:

1. Component tests exercise real feature logic with deterministic collaborators.
2. Adapter conformance tests run shared scenarios against real implementations and substitutes when feasible. Test real preferences in an isolated suite, storage in temporary directories, and transport adapters with controlled responses. Fake-only tests do not verify production adapters.
3. Composition tests verify wiring and lifetimes, including two display sessions sharing one feature service. Keep a few real-scheduler and offscreen renderer checks alongside deterministic tests.

External app automation, live permissions, audible output, and physical display checks remain separate opt-in acceptance checks. Fixtures can verify decoding and command translation, not establish that a live third-party app still honors its protocol.

Initial contract cases:

- Blank save deletes the goal and timer; clearing only the timer preserves text.
- Pause/resume preserve remaining duration; sleep counts against a running deadline.
- Expired-on-launch timers finish silently. Starting monitoring twice does not duplicate delivery.
- Completion records its handled state before requesting sound. This is not a guarantee of exactly-once audible delivery across a process crash or failed durable write.
- Canceling an editor discards only its draft, not timer actions already committed.
- Hover exit cannot close active editing. Explicit dismissal releases the protection.
- Focus transfer between displays has one editor owner and does not reset shared navigation accidentally.
- Late callbacks after cancellation, provider replacement, or teardown cannot alter current state.
- Capability flags match supported commands; unavailable/denied/failed states are distinguishable where consumers need them.
- Legacy saved data remains readable; malformed data follows a documented recovery policy.

## Implementation sequence

### 0. Establish the baseline and fork identity

- [x] Record background test results and an unsigned app build after the initial branding patch. A separate pre-change build was not run; these results are the baseline for subsequent extraction work.
- [x] Introduce `anotchup` in product metadata, menus, welcome/settings text, and project documentation. Remove upstream promotional claims while retaining attribution.
- [ ] Inventory remaining branding in localization, images, workflows, helper names, file paths, and persisted identifiers. Classify each as rename, attribution, or compatibility exception.
- [ ] Audit inherited release, update, website, and translation automation. Disable or isolate upstream publishing behavior before using it for this fork. Do not publish or provision credentials during this work.

Gate: existing tests pass, generated app metadata says `anotchup`, settings and goal data keep the same identifiers, and no upstream updater is enabled. Report remaining names rather than claim the entire rename is complete.

### 1. Add a repeatable verification entry point

- [x] Add one documented local command for deterministic component/contract tests and static boundary checks, plus an explicit unsigned-build option.
- [x] Retain the existing offscreen renderer checks and isolated preferences behavior.
- [x] Wire the same command into CI. Check path filters so package, script, and project changes trigger verification.
- [x] Record toolchain requirements from the actual successful baseline rather than copying upstream claims.

Gate: a fresh checkout can run the checks without private credentials, app activation, user input, permission prompts, or real-user data writes.

### 2. Perform mechanical source and project renames

- [ ] Rename the Xcode project, scheme, source root, entitlements paths, and build scripts to `anotchup` in one coordinated change. Update CI and documentation references.
- [ ] Use responsibility names for internal types: `NotchSession`, `NotchPanel`, and `AppComposition` where those responsibilities are established. Avoid replacing every `Boring` prefix with a new brand prefix.
- [ ] Rename helper product/types and both ends of the XPC protocol together; verify embedding and service resolution. Retain its old service identifier until the identity migration step if needed.
- [ ] Maintain a checked allowlist for legacy identifiers and attribution instead of blindly replacing strings or editing vendored binaries.

Gate: tests and unsigned app build pass; project/scheme enumeration, helper embedding, and client/service identifiers agree. No state schema change in this step.

### 3. Extract Working on as the reference component

- [x] Promote existing model/store tests into explicit behavior contracts before moving logic.
- [ ] Create the local Swift package and a Working on logic target with no SwiftUI/AppKit dependency. Separate existing native font/layout helpers from timer/text logic as needed.
- [x] Inject persistence, scheduling, time, and completion effects. Specify cancellation behavior and guard against stale callbacks. Preserve the wall-clock deadline policy.
- [ ] Separate editor draft state from saved state and focus effects. Keep draft cancellation distinct from committed timer commands.
- [x] Wire the production adapters at app composition; views consume injected feature state/actions.
- [x] Test two display consumers with one service, restart/reconstruction, completion ordering, scheduler cancellation, and legacy snapshots. The automated consumers are subscribers, not live display windows; actual display composition remains untested.

Gate: the app uses the extracted implementation, not a parallel copy. Existing behavior tests remain green; component tests do not import or launch the app. Run shared persistence cases against the real isolated preferences adapter and the test substitute.

### 4. Extract shell behavior and display composition

- [ ] Characterize hover, drag, expansion, preview dismissal, tab defaults, and editor protection before moving them.
- [ ] Extract deterministic shell transitions and layout decisions from `ContentView` and `BoringViewModel`.
- [ ] Introduce explicit display-session and editor-focus ownership. Preserve shared tab semantics.
- [ ] Move window creation, permission prompts, and cross-feature refresh wiring out of shell logic.
- [ ] Test focus transfer, display removal, stale delayed-close callbacks, lock/unlock transitions, and teardown without interacting with the real desktop.

Gate: shell tests require no camera/media service construction. One display's local events cannot corrupt another display's local state. Physical focus and camera-cutout readability remain manual acceptance items.

### 5. Extract media contracts

- [ ] Define normalized state, capabilities, command results, delivery context, and provider lifecycle.
- [ ] Inject provider construction and remove direct shell/coordinator access from media logic.
- [ ] Create common adapter cases with controlled transports for playback mapping, unavailable data, unsupported commands, and failures.
- [ ] Test provider switching and late artwork/lyrics/playback results, including cancellation and teardown.

Gate: consumers test against the same observable semantics required of production adapters. Real external-player smoke checks remain opt-in and are not claimed by fixture tests.

### 6. Extract remaining features one at a time

- [ ] Shelf: persistence round trips, missing files, bookmark failures, sharing completion, cancellation, and temporary-file ownership.
- [ ] Calendar: denied access, filtering, time boundaries, empty results versus failures, and stale query results.
- [ ] Camera: unavailable/denied states, request lifecycle, start/stop ownership, and teardown.
- [ ] System HUD/XPC: decoding validation, connection loss/reconnection, authorization changes, and cancellation.

Gate per feature: production wiring uses the new boundary, adapter contracts pass, and no new dependency on a sibling feature implementation appears. Do not extract all four in one patch.

### 7. Migrate remaining app identity deliberately

- [ ] Inventory UserDefaults, Shelf files/bookmarks, temporary storage, Keychain/authentication, login items, permissions, helper names, and update configuration before changing identifiers.
- [ ] Move toward `com.iameugenechang.anotchup` and a matching helper identity with explicit legacy reads/migration, not an empty new preferences domain.
- [ ] Specify precedence when both old and new data exist. Make migration idempotent and interruption-safe; do not delete the source data during initial migration.
- [ ] Test fresh install, existing `mynotch` data, already-migrated state, corrupt data, partial migration, and storage failures using isolated domains/directories.
- [ ] Document permissions that macOS may require again. Do not promise to migrate OS permission grants.

Gate: migration tests pass, the packaged helper resolves under the new identity, and preserved data can be reconstructed. No remote repository rename or release publication is implied.

## Agent execution rules

For each step:

1. Read this plan, relevant component contract, and current diff. Identify the exact slice and its dependencies.
2. Add characterization tests first when behavior is not already covered. Distinguish observed behavior from a desired behavior change.
3. Implement one boundary or one mechanical rename. Keep build-graph changes coordinated; do not mix them with unrelated feature edits.
4. Run focused tests, then the repository verification command and unsigned build when app wiring/project files change.
5. Inspect the diff for unexpected data identifiers, localization changes, upstream endpoints, and generated artifacts.
6. Update this checklist and record commands/results, exceptions, and the next unfinished slice. Never mark manual checks as passed from offscreen tests.

Prefer sequential work for shared composition, project, and migration files. If delegation is explicitly requested later, parallelize only independent components after contracts stabilize, with disjoint file ownership and one integration owner. The plan must work with one coding agent; it must not depend on a council or concurrent agents.

Do not launch or replace the running app, play sounds, move the pointer, synthesize keys, capture the screen, request permissions, publish releases, or change remote repositories as part of normal verification.

## Initial execution record

The initial patch changes product metadata in both Debug and Release, visible Swift UI strings, fork links, and README content. It does not extract components, rename the Xcode project, migrate identifiers, update all translations/assets, or change release workflows.

Verification on Xcode 27.2 (27B52):

- `scripts/test-one-goal.sh`: 328 model/layout checks and 104 offscreen renderer checks passed, without audio.
- `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/anotchup-build CODE_SIGNING_ALLOWED=NO build`: passed. Release was not built.
- Generated app metadata: name, display name, and executable are `anotchup`; app and embedded helper identifiers retain their compatibility values.
- `plutil -lint boringNotch.xcodeproj/project.pbxproj` and `git diff --check`: passed.
- Build warnings include Sendable diagnostics in unchanged code and a MediaRemoteAdapter macOS 15.0 binary linked into a macOS 14.0 target. Build success does not establish macOS 14 runtime compatibility; investigate that mismatch before claiming support.
- No app launch, installation, permission prompt, interactive UI validation, or release publication was performed.

## First architecture slice

On the request to start rearchitecture, step 1 and the dependency/lifecycle portion of step 3 were done before the mechanical rename. This keeps naming changes out of the component diff. Steps 0 and 2 remain unfinished.

- Added `scripts/verify.sh` for boundary checks, existing behavior/renderer tests, adapter contracts, project validation, and whitespace checks. `--build` also compiles the unsigned app. CI uses the same default command; the unsigned app build was verified locally, not added to CI.
- Removed `OneGoalStore.shared`. The app delegate owns one store and injects it into each display tree. Startup/shutdown own monitoring and sound wiring.
- Added persistence and scheduling contracts with real adapters. Existing clock injection and completion callback remain. Canceled registrations are generation-guarded against late delivery.
- Added [Working on contracts](working-on-contract.md) and shared real/substitute conformance tests. Source-level checks are temporary guardrails until package targets enforce dependencies.
- Before changes, `scripts/test-one-goal.sh` passed 328 model/layout and 104 renderer checks. After changes, `scripts/verify.sh --build` passed those checks plus 67 contract checks and the unsigned Debug app build. No app was launched or installed; no audio or permissions were invoked. Existing macOS 14/15 binary mismatch remains.

Toolchain used: macOS with full Xcode 27.2 (27B52), its selected Swift/macOS SDK, Python 3, Bash, Git, and `plutil`. Other Xcode versions have not been verified. The full build resolves public Swift packages and may require network access. Background tests compile production sources directly and do not need package downloads or private credentials.

Next architecture slice: introduce the local Working on logic target and test target, keeping native rendering helpers and adapters outside it. Then extract editor draft/focus state and add composition tests. The branding/automation audit and coordinated mechanical rename remain separate work; inherited publishing automation is not cleared for use.

## Current compatibility exceptions

Until their migration steps are complete:

- Xcode project/scheme/source root: `boringNotch`.
- App bundle/preferences identity: `com.iameugenechang.mynotch`.
- Helper identity: `com.iameugenechang.mynotch.BoringNotchXPCHelper`.
- Working on persistence: `oneGoal.current` and existing appearance keys.
- Shelf storage: the existing Application Support `boringNotch/Shelf` location.
- Repository URL: `https://github.com/iameugenechang/mynotch`.

These are compatibility details, not product branding. Remove an exception only when its replacement is implemented and verified.
