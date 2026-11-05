# Working on

## Behavior

Click the caption to open Working on beside Home and Shelf. With nothing saved, use the tab or right-click the notch and choose Working on. The empty state adds no caption or timer.

The editor asks "What are you working on?" Save or Return commits the text. Blank text clears it. Cancel, Escape, an upward close gesture, or switching to another app discards the text draft and closes the editor. Moving the pointer away does not dismiss active editing. Done deletes the saved text and countdown. There are no lists, history, or completion statistics.

The timer card offers 15/25/50-minute presets and a visible Custom control for minutes and seconds. Durations range from one second to 24 hours. Starting a countdown saves the current text. Pause freezes the remaining time; Resume rebuilds the deadline. Restart uses the original duration, including custom seconds. Clear removes only the timer. Dismissing an unsaved text draft does not undo timer actions already taken.

Expiry leaves the text in place and marks the countdown Finished. Settings > Working on offers Glass (default), Tink, Pop, Ping, and Silent, with volume and preview controls. One app-level monitor handles expiry once, even with multiple displays. A countdown that expired while the app was closed is marked finished silently on launch.

## Layout and settings

- The caption uses the main notch's full width, black background, and clipping shape, including media extensions. It is not a separate badge or nested notch.
- The caption stays at the bottom during expansion. Standard and inline previews reserve a footer rather than placing it over preview content.
- Settings > Working on controls font size (7pt default), text padding, and vertical offset. Caption height follows native font metrics. Offset can place the text below the physical camera cutout.
- The countdown can be an underline at the top or bottom of the caption, or a ring around the visualizer. The underline remembers the collapsed inner width through expansion and previews. The ring stays 20 by 20 points with a centered 10 by 10 point spectrum.
- Text, underline, and ring use the existing Player tinting setting. There is no separate caption color setting.
- Settings > Media > Keep visible while paused is enabled by default. It keeps real track metadata visible, not the startup placeholder. Turning it off restores the inactivity timeout.
- Right-click offers Working on, countdown controls when applicable, Settings, and Quit anotchup.
- Display selection, all-displays mode, and existing media/fullscreen controls remain in place. All displays share the same saved text and countdown.

Physical readability still needs a person looking at the display. Offscreen geometry cannot tell whether a camera cutout hides text.

## Implementation and compatibility

The feature was previously called One Goal. Internal `OneGoal` type names, persisted fields, and preference keys remain unchanged. Moving the implementation into a package does not reset the text, timer, or appearance settings.

- `Packages/AnotchupFeatures/Sources/WorkingOn/OneGoal.swift` contains the Codable snapshot and duration parser. `boringNotch/models/OneGoalPresentation.swift` keeps sound choices and deterministic caption/layout rules in the app.
- `Packages/AnotchupFeatures/Sources/WorkingOn/OneGoalStore.swift` owns saved-state transitions through injected persistence, scheduling, and time. `Packages/AnotchupFeatures/Sources/WorkingOnAdapters/OneGoalAdapters.swift` supplies isolated-testable UserDefaults storage under the existing `oneGoal.current` key and the real run-loop scheduler. Emptying the text or choosing Done removes the key. Optional pause and handled-completion fields keep older snapshots readable.
- Running countdowns use a wall-clock deadline, not a decrementing counter, so sleep time is included. Paused countdowns retain their remaining duration across relaunches. Tests inject a clock without changing production timekeeping.
- The app delegate owns one store shared across display view trees, starts monitoring at launch, and stops it at termination. The store retains a scheduler token, cancels it for paused/finished/removed timers, and rejects stale callbacks. The real adapter uses the main run loop's common modes. Completion saves the handled flag before invoking the sound callback, without promising crash-safe exactly-once audio.
- `Packages/AnotchupFeatures/Sources/WorkingOn/OneGoalEditorSession.swift` owns each editor's draft, duration fields, timer actions, and focus requests. `boringNotch/components/OneGoal/OneGoalViews.swift` renders that state and bridges native focus; it observes both the session and shared store. `boringNotch/ContentView.swift` supplies the store and owns the shared clipping shape and stable timer-width tracking.
- `components/Music/MusicVisualizer.swift` lays out its actual AppKit layers within their current bounds. `models/PlaybackState.swift` defines the tested paused-media visibility policy.
- Only an explicitly opened Working on editor permits its panel to become key. Hover closure stays blocked while editing; explicit dismissal releases that protection.
- The app is named anotchup. It retains `com.iameugenechang.mynotch` and its existing helper identifier for compatibility. The upstream updater does not start. See the [architecture and implementation plan](architecture-plan.md) for the staged source and identity migration.

## Background checks

Run:

```bash
scripts/verify.sh
```

The command runs boundary checks, SwiftPM XCTest cases against the public package API, standalone native presentation checks, and Xcode project validation. It needs no third-party test framework or package downloads and does not build or launch the app by default. `scripts/test-one-goal.sh` remains the focused test runner. Run only the package tests with `xcrun swift test --package-path Packages/AnotchupFeatures`.

`Packages/AnotchupFeatures/Tests/WorkingOnTests/OneGoalTests.swift` checks normalization, Unicode storage, corrupt/legacy snapshots, rename compatibility, duration bounds and parsing, countdown fractions, pause/resume/restart, clearing/completion, sleep/relaunch behavior, single completion callback delivery, and the real Foundation completion scheduler. `Tests/OneGoalPresentationTests.swift` covers collapsed, expanded, and preview footer geometry across font heights and offsets, plus the paused-player visibility policy.

`Packages/AnotchupFeatures/Tests/WorkingOnTests/OneGoalContractTests.swift` runs shared persistence and scheduling cases against real adapters and test substitutes. It also checks shared subscribers, completion ordering, stale callbacks, reconstruction, and teardown. See [Working on component contracts](working-on-contract.md) for guarantees and limits.

`Packages/AnotchupFeatures/Tests/WorkingOnTests/OneGoalEditorSessionTests.swift` composes real sessions with the store and both persistence adapters. It checks draft isolation, focus requests, validation, timer commit/cancel behavior, reconstruction, and editor teardown. These are component composition tests, not native window or keyboard-focus tests.

`Tests/OneGoalRendererTests.swift` creates offscreen AppKit spectrum layers without windows or activation. It checks centering, clipping, resizing, paused bars, native font metrics, and sound-file loading. It never plays audio.

All suites leave the running app and its preferences alone. They do not move the pointer, synthesize keys, change app focus, capture the screen, hide applications, or request Accessibility access. The previous interactive UI smoke script has been removed rather than run during normal work.

GitHub Actions runs `scripts/verify.sh` on macOS. To also check app compilation locally without opening it:

```bash
scripts/verify.sh --build
```

The unsigned Debug build goes to `/tmp/anotchup-build` by default. Set `ANOTCHUP_BUILD_DIR` to choose another directory. Verification used Xcode 27.2 (27B52) and Python 3; other Xcode versions have not been verified.

## Manual acceptance checks

These are not automated background checks. Run them only when you choose to interact with the app. Current model/renderer passes do not establish that every UI interaction works.

- [ ] Check caption readability on the physical display with short, long, and Unicode text, different font sizes, and crowded menu bars.
- [ ] Save with Return; cancel with Escape, focus loss, and upward swipe. Confirm hover exit preserves editing and explicit dismissal discards only the draft.
- [ ] Try presets and custom seconds; pause/resume, restart, clear, and relaunch. Confirm only the current text/countdown returns.
- [ ] Let a timer finish while the editor is closed and open. Check each sound and volume, and confirm expiry never clears the text or plays twice.
- [ ] Compare the underline through expansion, standard/inline previews, battery notices, and volume/brightness HUDs. Confirm the caption stays below preview content.
- [ ] Check the ring around playing and paused bars in collapsed and expanded views. Verify Player tinting applies to text and progress together.
- [ ] Toggle Keep visible while paused, stop the media app, and check Home, Shelf drag-and-drop, calendar, and camera.
- [ ] Choose Done and relaunch; verify no saved text or timer returns. Check right-click Settings and Quit.
- [ ] Check fullscreen Spaces, external displays, all-displays mode, display reconnects, and editor focus transfer between displays.
