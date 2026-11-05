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
- Keep naming, behavior, and data migration changes separately reviewable. The coordinated rename below includes the Shelf path compatibility code and is verified before the next shell change.

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
- [x] Inventory remaining branding in localization, images, workflows, helper names, file paths, and persisted identifiers. Classify each as rename, attribution, or compatibility exception.
- [x] Audit inherited release, update, website, and translation automation. Disable or isolate upstream publishing behavior before using it for this fork. Do not publish or provision credentials during this work.

Gate: existing tests pass, generated app metadata says `anotchup`, settings and goal data keep the same identifiers, and no upstream updater is enabled. Report remaining names rather than claim the entire rename is complete.

### 1. Add a repeatable verification entry point

- [x] Add one documented local command for deterministic component/contract tests and static boundary checks, plus an explicit unsigned-build option.
- [x] Retain the existing offscreen renderer checks and isolated preferences behavior.
- [x] Wire the same command into CI. Check path filters so package, script, and project changes trigger verification.
- [x] Record toolchain requirements from the actual successful baseline rather than copying upstream claims.

Gate: a fresh checkout can run the checks without private credentials, app activation, user input, permission prompts, or real-user data writes.

### 2. Perform mechanical source and project renames

- [x] Rename the Xcode project, scheme, source root, entitlements paths, and build scripts to `anotchup` in one coordinated change. Update CI and documentation references.
- [x] Rename app-owned branded types to `Anotchup`, as requested. Extracted components retain responsibility names. Further responsibility naming follows actual ownership extraction rather than implying it is already done.
- [x] Rename helper product/types and both ends of the XPC protocol together; verify embedding and matching service identifiers. Signed runtime service resolution remains untested.
- [x] Maintain a checked allowlist for legacy identifiers and attribution instead of blindly replacing strings or editing vendored binaries.

Gate: tests and unsigned app build pass; project/scheme enumeration, helper embedding, and client/service identifiers agree. No state schema change. The Shelf directory rename uses a tested compatibility copy, documented in [the rename contract](rename-contract.md).

### 3. Extract Working on as the reference component

- [x] Promote existing model/store tests into explicit behavior contracts before moving logic.
- [x] Create the local Swift package and a Working on logic target with no SwiftUI/AppKit dependency. Separate existing native font/layout helpers from timer/text logic as needed.
- [x] Inject persistence, scheduling, time, and completion effects. Specify cancellation behavior and guard against stale callbacks. Preserve the wall-clock deadline policy.
- [x] Separate editor draft state from saved state and focus effects. Keep draft cancellation distinct from committed timer commands.
- [x] Wire the production adapters at app composition; views consume injected feature state/actions.
- [x] Test two display consumers with one service, restart/reconstruction, completion ordering, scheduler cancellation, and legacy snapshots. The automated consumers are subscribers and editor sessions, not live display windows; actual display composition remains untested.

Gate: the app uses the extracted implementation, not a parallel copy. Existing behavior tests remain green; component tests do not import or launch the app. Run shared persistence cases against the real isolated preferences adapter and the test substitute.

### 4. Extract shell behavior and display composition

- [x] Characterize hover-open/exit, battery/sharing close guards, and editor close protection.
- [x] Extract hover decisions and pending-ticket ownership into `NotchShell`, with one session per display view model.
- [x] Extract drag-exit, delayed width tracking, preview dismissal, and tab-default decisions, with deterministic tests.
- [ ] Finish expansion/geometry policy and native display lifecycle composition.
- [ ] Complete display-session and editor-focus ownership. Preserve shared tab semantics.
- [ ] Move window creation, permission prompts, and cross-feature refresh wiring out of shell logic.
- [x] Test stale/replaced/canceled hover tickets, recreation, and independent sessions without native services.
- [x] Move shortcut auto-close under each display owner and test its policy, stale tickets, independent deadlines, and separation from hover cancellation.
- [x] Extract delayed-work lifetime ownership with shared real/manual scheduler contracts. Test token cancellation/release, terminal invalidation, stale delivery, independent displays, and reentrant effects.
- [ ] Test host lifecycle-event wiring, focus transfer, actual display removal, lock/unlock, and remaining teardown paths without interacting with the real desktop. Package lifetime tests do not exercise app-delegate events or SwiftUI trees.

Gate: shell tests require no camera/media service construction. One display's local events cannot corrupt another display's local state. Physical focus and camera-cutout readability remain manual acceptance items.

### 5. Extract media contracts

- [x] Define normalized state, capabilities, command results, delivery context, and provider lifecycle. Legacy commands report submission, not transport success.
- [x] Inject provider construction and remove direct shell/coordinator access from media logic.
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
- `xcodebuild -project anotchup.xcodeproj -scheme anotchup -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/anotchup-build CODE_SIGNING_ALLOWED=NO build`: passed. Release was not built.
- Generated app metadata: name, display name, and executable are `anotchup`; app and embedded helper identifiers retain their compatibility values.
- `plutil -lint anotchup.xcodeproj/project.pbxproj` and `git diff --check`: passed.
- Build warnings include Sendable diagnostics in unchanged code and a MediaRemoteAdapter macOS 15.0 binary linked into a macOS 14.0 target. Build success does not establish macOS 14 runtime compatibility; investigate that mismatch before claiming support.
- No app launch, installation, permission prompt, interactive UI validation, or release publication was performed.

## First architecture slice

On the request to start rearchitecture, step 1 and the dependency/lifecycle portion of step 3 were done before the mechanical rename. This kept naming changes out of that component diff. Steps 0 and 2 were unfinished at that point.

- Added `scripts/verify.sh` for boundary checks, existing behavior/renderer tests, adapter contracts, project validation, and whitespace checks. `--build` also compiles the unsigned app. CI uses the same default command; the unsigned app build was verified locally, not added to CI.
- Removed `OneGoalStore.shared`. The app delegate owns one store and injects it into each display tree. Startup/shutdown own monitoring and sound wiring.
- Added persistence and scheduling contracts with real adapters. Existing clock injection and completion callback remain. Canceled registrations are generation-guarded against late delivery.
- Added [Working on contracts](working-on-contract.md) and shared real/substitute conformance tests. Source-level checks are temporary guardrails until package targets enforce dependencies.
- Before changes, `scripts/test-one-goal.sh` passed 328 model/layout and 104 renderer checks. After changes, `scripts/verify.sh --build` passed those checks plus 67 contract checks and the unsigned Debug app build. No app was launched or installed; no audio or permissions were invoked. Existing macOS 14/15 binary mismatch remains.

Toolchain used: macOS with full Xcode 27.2 (27B52), its selected Swift/macOS SDK, Python 3, Bash, Git, and `plutil`. Other Xcode versions have not been verified. The full build resolves public Swift packages and may require network access. Background tests do not need package downloads or private credentials.

## Package extraction slice

- Added `Packages/AnotchupFeatures` with `WorkingOn`, `WorkingOnAdapters`, and `WorkingOnTests` targets. The logic target imports only Foundation and Combine. Adapters depend on logic, not the reverse. The package has no external dependencies and uses Swift tools 5.9 with a macOS 14 minimum.
- Moved snapshot, duration parser, state transitions, contracts, and adapters into the package. The app links both library products instead of compiling duplicate source files. Public initializers preserve the existing snapshot defaults and persisted fields. No data or app identifier changed.
- Kept native layout and sound choices in `anotchup/models/OneGoalPresentation.swift`. Moved layout/media checks to `Tests/OneGoalPresentationTests.swift` so the feature tests do not import app presentation code.
- Converted behavior and adapter-contract runners to XCTest using public imports, without `@testable`. Real scheduler tests yield the main actor with asynchronous waits; blocking its executor with a nested run loop prevented callback delivery under XCTest.
- Extended boundary checks to inspect the package graph and reject app-local copies of feature types. Added four Python test cases for the rules.
- `scripts/verify.sh --build` passed: two XCTest cases containing 110 behavior and 67 contract assertions, 218 presentation/media checks, 104 renderer checks, four boundary-rule test cases, project validation, whitespace checks, and the unsigned Debug build. All 499 existing assertions/checks remain. No app launch, installation, audio, or permission interaction occurred.
- The build still reports concurrency warnings in unchanged app code and the existing MediaRemoteAdapter macOS 14/15 binary mismatch. No package warnings were observed. Only Xcode 27.2 (27B52) was verified; no Release build or interactive checks were run.

## Editor session slice

- Added `OneGoalEditorSession` to `WorkingOn`. It owns text/duration drafts, custom-duration mode, timer action selection, and focus requests. It uses the shared store directly rather than adding another service protocol.
- `OneGoalView(store:)` retains one session and observes the same store supplied by `ContentView`. UI labels, styling, native focus, window activation, and shell editor protection remain in the app. The initial deferred focus request now checks cancellation and session activity.
- Preserved timer command policy: start/apply commits text; pause/resume/restart/clear do not. Cancel/disappear drops the text draft without undoing committed actions. Repeated begin calls preserve live edits; closed sessions reject late commands. Simultaneous drafts are independent and explicit saves remain last-writer-wins.
- Added nine public-API XCTest cases, each run with memory and isolated UserDefaults persistence. These cover editor lifecycle and validation, duration controls, two sessions sharing one store/monitor, focus-request isolation, reconstruction, and editor teardown. They do not create windows or validate physical focus transfer.
- `scripts/verify.sh --build` passed the editor tests, existing 499 assertions/checks, four boundary-rule test cases, project validation, whitespace checks, and unsigned Debug build. No app launch, installation, audio, or permission interaction occurred. The existing MediaRemoteAdapter macOS 14/15 warning remains; native focus acceptance is still manual.

## Shell hover slice

- Added the independent `NotchShell` library and public-API test target. It owns hover decisions and opaque pending-action tickets, not native tasks or window effects. See [the shell contract](notch-shell-contract.md).
- Each `AnotchupViewModel` owns a session. Open, successful close, and destruction synchronously invalidate tickets; the common close guard now uses package policy. `ContentView` routes hover and protection-release delays through one host function and cancels its local tasks on disappearance. Shared tab selection and native focus transfer are unchanged.
- Kept the existing hover duration and 100 ms close delay. Pending opens now recheck the hover preference at delivery. Replaced/canceled callbacks cannot close a newly opened notch or consume another session's request.
- Nine deterministic tests cover decision matrices, one-shot delivery, cancellation/replacement, protection at delivery, recreation, and display-session isolation. They exercise package contracts, not actual display removal or SwiftUI callback ordering. Boundary checks now enforce separation of `NotchShell` and `WorkingOn`.
- `scripts/verify.sh --build` passed all 20 XCTest cases across the two test targets, the existing 499 assertions/checks, four Python boundary tests, project/whitespace checks, and unsigned Debug build. No app launch, sound, installation, or permission interaction occurred. The existing MediaRemoteAdapter macOS 14/15 warning remains.

The next slice at this point was shortcut auto-close. It is recorded below; shared navigation/focus transfer and other delayed work remain unfinished.

## Coordinated rename and shortcut slice

- Renamed the Xcode project/scheme, source paths, app-owned types, localization product keys, resources, and XPC helper to anotchup. The main preferences domain stays unchanged. Helper client/service identifiers and generated app metadata agree. `xcodebuild -list -project anotchup.xcodeproj` lists the renamed targets and schemes.
- Added checked attribution/compatibility exceptions and temporary-directory Shelf migration tests. The new Shelf path wins; migration copies without deleting the original, with failure cleanup and retry. See [the rename contract](rename-contract.md).
- Quarantined inherited release, nightly, website, and translation workflows outside `.github/workflows`. Active unsigned build/check paths now use the renamed project. Release licensing, signing, and destination configuration are not complete.
- Verified the rename with `scripts/verify.sh --build` before continuing shell changes. Then generalized pending-action tickets and moved the three-second shortcut close from the app delegate to each display view model. Pointer cancellation affects only hover; reopen/close/teardown invalidate both lanes. App lifecycle paths cancel pending work; removed owners release subscriptions.
- Added six public-API shortcut contract tests. Intentional change: one display's shortcut no longer cancels another display's deadline. Tests verify component policy, not real window lifecycle or task delivery.
- `scripts/verify.sh --build` passed 26 XCTest cases, the existing 499 assertions/checks, four boundary-rule and four identity Python tests, 39 workflow utility tests, Shelf migration tests, project/whitespace checks, and the unsigned Debug build. No app launch, installation, permission request, audio, real-user migration, or publication occurred. The existing MediaRemoteAdapter macOS 14/15 mismatch remains; signed XPC runtime behavior and native focus remain untested.

The next slice was delayed-work lifetime ownership, recorded below. Shared navigation/focus transfer and host lifecycle-event wiring remain unfinished.

## Delayed-work lifetime slice

- Added `NotchInteractionLifetime` to `NotchShell`. It owns per-display hover and shortcut registrations, reads current state at delivery, and removes completed work before applying effects. Reentrant effects cannot erase new registrations. Reusable cancellation and terminal invalidation are separate operations.
- Added the one-shot `NotchDelayScheduling` contract and `TaskNotchDelayScheduler` in the new `NotchShellAdapters` target. Cancellation/token release suppress pending delivery; even zero delay is deferred. Logic does not import concrete adapters or sleep directly. No external package dependencies were added.
- App composition injects the adapter into each main-actor view model. Both hover and shortcut work now use the package owner rather than separate app-owned tasks. Callbacks capture models weakly, tokens cancel on release, and explicit destruction permanently invalidates the owner. Shared tab/focus policy and existing delay values are unchanged.
- Added eight component lifetime tests and two shared adapter-conformance tests. Tests cover cancellation-token ownership, stale callbacks, independent displays/lanes, recreation, reentrant effects, callback/owner release, and real task delivery. Manual time handles policy cases; bounded asynchronous waits exercise the production adapter. Tests do not construct app view models or native windows.
- `scripts/verify.sh --build` passed 36 XCTest cases, the existing 499 assertions/checks, four boundary-rule and four identity Python tests, 39 workflow utility tests, Shelf migration tests, project/whitespace checks, and the unsigned Debug build. No app launch, installation, audio, permission prompt, or desktop interaction occurred. The existing MediaRemoteAdapter macOS 14/15 warning remains. Native focus and host lifecycle-event wiring are still untested.

## Shared navigation and presentation lifetime slice

- Added `NotchNavigation`: shared tab selection, registered display lifetime IDs, editor requests, and native focus ownership. Close-default precedence is unchanged. Native focus transfer no longer scans application windows; either callback order preserves the destination editor. Removed windows cannot reset shared tabs.
- Added drag and resize lanes to the tested interaction owner. The existing 500 ms drag exit and 700 ms width-tracking delay now use injected scheduling and delivery-time guards. Views retain geometry measurement and animation, not task ownership.
- Moved compact/expanded preview timers to independent owner lanes. Replacement, cancellation, lock/unlock, and termination reject old hide callbacks. Preview updates are atomic on the main actor. Invalid HUD notification payload types are ignored rather than force-cast.
- Added six test cases for navigation/transfer, drag protection, resize guards, independent preview replacement, and teardown. `scripts/verify.sh --build` passed 42 XCTest cases plus the existing verification suites and unsigned Debug build. No app or native focus operation was launched.
- Native lifecycle-event composition, geometry, camera commands, and cross-feature refresh remain in the host. The full-plan request is still in progress; these tests do not complete the shell checklist.

## Media core slice

`MediaFeature` now owns provider selection, playback snapshots, command/capability policy, and revision validation. App composition constructs native providers and wires preview effects. Native lyrics/artwork/color completion checks reject old revisions. Five component tests and the unsigned Debug build pass (`/tmp/anotchup-media-build.log`, 47 XCTest cases plus existing checks). Production transport conformance is not yet covered. See [the media contract](media-contract.md).

## Current compatibility exceptions

- App bundle/preferences identity: `com.iameugenechang.mynotch`.
- Working on persistence: `oneGoal.current` and existing appearance keys.
- Legacy Shelf reads and external media authorization identity, listed in [the rename contract](rename-contract.md).
- Repository URL: `https://github.com/iameugenechang/mynotch`.
- Upstream attribution and archived external publishing history.

The project/scheme/source root are now `anotchup`; the helper is `com.iameugenechang.mynotch.AnotchupXPCHelper`. These are no longer pending renames. A future main bundle-identity migration remains separate work.
