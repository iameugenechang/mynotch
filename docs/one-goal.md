# One Goal

## Behavior

Click the countdown ring or the small goal text below the notch to open the One Goal tab next to Shelf. The ring is available without music or an active goal. Hovering those controls does not open another tab first.

Save or Return commits the goal text. Blank or whitespace-only text clears it. Cancel or Escape discards the text draft and collapses the notch. Clicking another app also dismisses the draft. Complete clears the saved goal and countdown immediately.

Enter 1 to 1440 minutes and click Start to save the current goal and begin an optional countdown. Restart starts the entered duration again. Clear removes only the countdown. Cancel does not undo a countdown already started or cleared. The ring shows the remaining fraction; its tooltip and the editor show the exact remaining time. Expiry is silent and never completes a goal.

## State and layout

- `models/OneGoal.swift` contains the current text and optional countdown duration/deadline.
- `models/OneGoalStore.swift` writes one Codable snapshot to UserDefaults under `oneGoal.current`. Emptying or completing the goal removes the key. There is no completion history.
- A deadline, rather than a decrementing counter, keeps the countdown correct across sleep and relaunches. Remaining time is clamped to zero and the original duration.
- `components/OneGoal/OneGoalViews.swift` contains the ring, the 8pt truncated label, and the editor. TimelineView refreshes countdown displays once a second without notifications, sounds, or continuous animations.
- The countdown ring sits inside a compact left shoulder of the same black notch shape. A one-sided 32 point inset reserves room for it; a matching half-width offset keeps the camera spacer centered on the physical camera. There is no separate timer bubble. The expanded body keeps its original 640 by 190 point size.
- The goal forms a smaller attached lower tab: square top corners, rounded bottom corners, and no gap at the notch's lower edge. A one-point background overlap covers fractional-pixel seams. The tab hugs its text up to a width cap and never widens the main notch body. It stays attached in collapsed and expanded modes, including below temporary music/HUD content. No empty-state label is drawn. Extra transparent window space accommodates the lower tab.
- Right-clicking the notch, goal text, or countdown ring offers Settings and Quit mynotch.
- Goal visibility is independent of media fullscreen hiding. Existing selected-display/all-displays settings still decide where notch windows exist. All displays share one saved goal.
- Only the explicitly opened One Goal editor allows its panel to become key. Automatic hover/drop/shortcut closure is blocked during editing. Save, Cancel, Complete, and losing keyboard focus end that protection. Switching tabs releases input focus.
- The app has its own bundle identifier, `com.iameugenechang.mynotch`, and helper identifier. The upstream update feed is removed and the updater is not started.

## Automated checks

Run `scripts/test-one-goal.sh`. It compiles the actual model/store against an isolated preferences suite and checks normalization, persistence, completion, invalid state, duration limits, expiry, ring fractions, and sleep/relaunch behavior. It does not drive the macOS interface.

Build the existing `boringNotch` scheme. The product is `mynotch.app`.

For the optional native UI smoke test, run:

```bash
xcrun swift Tests/OneGoalUISmoke.swift /tmp/mynotch-build/Build/Products/Debug/mynotch.app
```

This requires Accessibility permission and interacts with the real interface. It refuses to overwrite an existing saved goal. It checks keyboard entry, hover, navigation, countdown controls, relaunch persistence, text-sized labels, unchanged notch dimensions, loss of focus, completion, and right-click Quit. On success it leaves no saved goal and quits the test app through the notch menu. It temporarily skips upstream onboarding through launch arguments, without changing the saved onboarding preference. To test an isolated copy with a different bundle identifier, set `MYNOTCH_UI_BUNDLE_ID` to that identifier.

## Manual acceptance checks

Checked items below passed native smoke testing on one notched MacBook display. The remaining cases need suitable displays or further manual testing. A successful build or model test alone does not prove these interactions.

- [x] With music idle, click the faint ring and type a goal. Save with Return.
- [x] Focus another app. Confirm the 8pt goal remains visible while collapsed.
- [x] Hover the ring without clicking. Confirm another notch tab does not replace the click target, and moving onto the notch still expands it.
- [x] Click the goal. Move the pointer away and continue typing; the editor must stay open.
- [x] Cancel with Escape and by clicking another app. Confirm unsaved text is discarded and the other app keeps keyboard focus.
- [x] Switch from One Goal to Home/Shelf. Confirm the editor exits and both tabs remain navigable.
- [x] Quit and relaunch. Confirm only the saved active goal/countdown return.
- [ ] Start a one-minute countdown, sleep/wake, and let it expire. Confirm the ring empties without sound, notification, or goal completion.
- [x] Clear the countdown, then complete a goal. Confirm each action clears only the intended state, and a completed goal does not return after relaunch.
- [x] Save and reopen short and long goals. Confirm the lower tab hugs the text up to its width cap, stays centered below the camera, and retains the full saved text. The notch body's size must not change, and the tab must join its lower edge with no gap in either collapsed or expanded mode.
- [x] Confirm the countdown ring is inside the notch body and its click target stays clear of the physical camera.
- [x] Right-click the notch and choose Quit mynotch. Confirm Settings remains available and Quit terminates the app.
- [ ] Try Unicode/emoji, pasted newlines, and whitespace-only text in the interface. Confirm tail truncation, full tooltip text, and an empty collapsed state.
- [ ] Check playing/paused music, inline and standard sneak peeks, battery notices, volume/brightness HUDs, drag-and-drop Shelf, calendar, and camera.
- [ ] Test custom notch heights, smaller display scaling, and a crowded menu bar. The ring sits in a compact left shoulder of the notch; verify that nearby menu items remain usable.
- [ ] Test full-screen Spaces on notched and external displays, all-displays mode, and unplugging/reconnecting a display. Open the editor on each display and verify focus stays on the clicked one.
