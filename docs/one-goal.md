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
- Right-click offers Working on, countdown controls when applicable, Settings, and Quit mynotch.
- Display selection, all-displays mode, and existing media/fullscreen controls remain in place. All displays share the same saved text and countdown.

Physical readability still needs a person looking at the display. Offscreen geometry cannot tell whether a camera cutout hides text.

## Implementation and compatibility

The feature was previously called One Goal. Internal `OneGoal` type names, source/test paths, and preference keys remain unchanged to keep saved data and settings compatible. Renaming the feature does not reset the text, timer, or appearance settings.

- `models/OneGoal.swift` contains the Codable snapshot, duration parser, sound choices, and deterministic caption/layout rules.
- `models/OneGoalStore.swift` persists one snapshot under the existing `oneGoal.current` key. Emptying the text or choosing Done removes the key. Optional pause and handled-completion fields keep older snapshots readable.
- Running countdowns use a wall-clock deadline, not a decrementing counter, so sleep time is included. Paused countdowns retain their remaining duration across relaunches. Tests inject a clock without changing production timekeeping.
- The store owns one completion monitor in the main run loop's common modes. It saves the handled flag before invoking the sound callback and stops monitoring paused, finished, or removed timers.
- `components/OneGoal/OneGoalViews.swift` contains the caption, timer styles, settings, and editor. `ContentView.swift` owns the shared clipping shape and stable timer-width tracking.
- `components/Music/MusicVisualizer.swift` lays out its actual AppKit layers within their current bounds. `models/PlaybackState.swift` defines the tested paused-media visibility policy.
- Only an explicitly opened Working on editor permits its panel to become key. Hover closure stays blocked while editing; explicit dismissal releases that protection.
- The fork uses `com.iameugenechang.mynotch` and its own helper identifier. The upstream updater does not start.

## Background checks

Run:

```bash
scripts/test-one-goal.sh
```

The script compiles production sources directly with the macOS SDK. It needs no third-party test framework and does not build or launch the app.

`Tests/OneGoalTests.swift` checks normalization, Unicode storage, corrupt/legacy snapshots, rename compatibility, duration bounds and parsing, countdown fractions, pause/resume/restart, clearing/completion, sleep/relaunch behavior, exactly-once completion, and the real Foundation completion scheduler. Layout checks cover collapsed, expanded, and preview footer geometry across font heights and offsets. Media checks cover the paused-player visibility policy.

`Tests/OneGoalRendererTests.swift` creates offscreen AppKit spectrum layers without windows or activation. It checks centering, clipping, resizing, paused bars, native font metrics, and sound-file loading. It never plays audio.

Both suites leave the running app and its preferences alone. They do not move the pointer, synthesize keys, change app focus, capture the screen, hide applications, or request Accessibility access. The previous interactive UI smoke script has been removed rather than run during normal work.

GitHub Actions runs these same checks on macOS. To check app compilation separately without opening it:

```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/mynotch-build CODE_SIGNING_ALLOWED=NO build
```

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
