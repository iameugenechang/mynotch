# One Goal

## Behavior

Click the centered goal caption inside the menu-bar-height notch to open the One Goal tab next to Shelf. With no active goal, use the One Goal tab or right-click the notch and select One Goal. Nothing extra is drawn in the empty state. Hovering the caption does not open another tab first.

Save or Return commits the goal text. Blank or whitespace-only text clears it. Cancel or Escape discards the text draft and collapses the notch. Clicking another app also dismisses the draft. Complete clears the saved goal and countdown immediately.

Enter 1 to 1440 minutes and click Start to save the current goal and begin an optional countdown. Restart starts the entered duration again. Clear removes only the countdown. Cancel does not undo a countdown already started or cleared. A 1pt underline beneath the goal shows the remaining fraction; the caption tooltip and editor show the exact remaining time. Without a countdown, there is no line or empty track. Expiry is silent and never completes a goal.

## State and layout

- `models/OneGoal.swift` contains the current text and optional countdown duration/deadline.
- `models/OneGoalStore.swift` writes one Codable snapshot to UserDefaults under `oneGoal.current`. Emptying or completing the goal removes the key. There is no completion history.
- A deadline, rather than a decrementing counter, keeps the countdown correct across sleep and relaunches. Remaining time is clamped to zero and the original duration.
- `components/OneGoal/OneGoalViews.swift` contains the 8pt caption, countdown underline, and editor. TimelineView refreshes the underline and remaining time once a second without notifications, sounds, or continuous animations.
- There is no separate timer icon or extra notch shoulder. The music layout is symmetric again. The expanded body keeps its original 640 by 190 point size.
- The caption is forced into the bottom 12pt of the menu bar, horizontally centered over the notch. Its 6pt invisible click extension goes upward, keeping the full 18pt target inside the bar. There is no lip or separate caption backing, and neither the text nor underline extends below the bar. The collapsed header is constrained to that same height. The caption stays pinned to this position when expanded.
- Menu-bar height comes from the selected display's frame/visible-frame top inset, with a status-bar/notch-height fallback when the bar is auto-hidden. The tested display reports a 33pt menu bar and a 32pt camera safe area. Text placement deliberately ignores the safe-area floor for this experiment. UI geometry checks prove the bounds, not whether the physical camera masks any glyphs; inspect readability on the actual display.
- Right-clicking the notch or goal caption offers One Goal, Settings, and Quit mynotch.
- Goal visibility is independent of media fullscreen hiding. Existing selected-display/all-displays settings still decide where notch windows exist. All displays share one saved goal.
- Only the explicitly opened One Goal editor allows its panel to become key. Automatic hover/drop/shortcut closure is blocked during editing. Save, Cancel, Complete, and losing keyboard focus end that protection. Switching tabs releases input focus.
- The app has its own bundle identifier, `com.iameugenechang.mynotch`, and helper identifier. The upstream update feed is removed and the updater is not started.

## Automated checks

Run `scripts/test-one-goal.sh`. It compiles the actual model/store against an isolated preferences suite and checks normalization, persistence, completion, invalid state, duration limits, expiry, countdown fractions, and sleep/relaunch behavior. It does not drive the macOS interface.

Build the existing `boringNotch` scheme. The product is `mynotch.app`.

For the optional native UI smoke test, run:

```bash
xcrun swift Tests/OneGoalUISmoke.swift /tmp/mynotch-build/Build/Products/Debug/mynotch.app
```

This requires Accessibility permission and interacts with the real interface. It refuses to overwrite an existing saved goal. It checks keyboard entry, hover, navigation, countdown controls, relaunch persistence, text-sized labels, unchanged notch dimensions, loss of focus, completion, and right-click Quit. On success it leaves no saved goal and quits the test app through the notch menu. It temporarily skips upstream onboarding through launch arguments, without changing the saved onboarding preference. To test an isolated copy with a different bundle identifier, set `MYNOTCH_UI_BUNDLE_ID` to that identifier.

## Manual acceptance checks

Checked items below passed native smoke testing on one notched MacBook display. The remaining cases need suitable displays or further manual testing. A successful build or model test alone does not prove these interactions.

- [x] With music idle and no active goal, open One Goal from the notch's right-click menu and save a goal with Return.
- [ ] Focus another app and inspect the physical display. Confirm the 8pt goal is readable inside the menu bar and not obscured by the camera.
- [x] Hover the caption without clicking. Confirm the notch stays collapsed, and normal notch hover still expands it.
- [x] Click the goal. Move the pointer away and continue typing; the editor must stay open.
- [x] Cancel with Escape and by clicking another app. Confirm unsaved text is discarded and the other app keeps keyboard focus.
- [x] Switch from One Goal to Home/Shelf. Confirm the editor exits and both tabs remain navigable.
- [x] Quit and relaunch. Confirm only the saved active goal/countdown return.
- [ ] Start a one-minute countdown, sleep/wake, and let it expire. Confirm the underline empties without sound, notification, or goal completion.
- [x] Clear the countdown, then complete a goal. Confirm each action clears only the intended state, and a completed goal does not return after relaunch.
- [x] Save and reopen short and long goals. Confirm the caption hugs the text up to its width cap and retains the full saved text. The notch body's size must not change. The caption stays horizontally centered, with its bottom edge at the menu bar's bottom in collapsed and expanded modes.
- [x] Confirm no standalone timer icon remains. Start a countdown and verify the caption's remaining time updates; clearing the countdown removes its progress state.
- [x] Right-click the notch and choose Quit mynotch. Confirm Settings remains available and Quit terminates the app.
- [ ] Try Unicode/emoji, pasted newlines, and whitespace-only text in the interface. Confirm tail truncation, full tooltip text, and an empty collapsed state.
- [ ] Check playing/paused music, inline and standard sneak peeks, battery notices, volume/brightness HUDs, drag-and-drop Shelf, calendar, and camera.
- [ ] Test custom notch heights, smaller display scaling, and a crowded menu bar. Verify that the caption stays readable and nearby menu items remain usable.
- [ ] Test full-screen Spaces on notched and external displays, all-displays mode, and unplugging/reconnecting a display. Open the editor on each display and verify focus stays on the clicked one.
