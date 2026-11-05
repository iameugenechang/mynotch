# Working on component contract

## Module boundary

`Packages/AnotchupFeatures` contains two libraries. `WorkingOn` owns snapshots, duration parsing, store transitions, and dependency contracts; it imports only Foundation and Combine. `WorkingOnAdapters` depends on `WorkingOn` and supplies UserDefaults persistence and run-loop scheduling. The app links both products. Native layout, sound choices, and SwiftUI remain in the app target.

The package test target imports the public APIs without `@testable` or an app host. There is no second app-local implementation of the feature.

## Ownership and inputs

`OneGoalStore` owns the saved `OneGoal` snapshot and countdown transitions. All access is on the main actor. Commands save text, start/pause/resume/restart/clear a countdown, complete the goal, and start/stop monitoring. Consumers observe read-only published state. Each `OneGoalEditorSession` owns its uncommitted draft, duration fields, custom-duration mode, and focus requests.

`AppDelegate` constructs one store and injects that instance into every display's SwiftUI tree. It starts monitoring at app launch, connects completion to the sound player, and stops monitoring at termination. Views do not create stores or discover one through a singleton. Previews explicitly supply an isolated preferences instance.

Time is an injected `() -> Date`. Running timers use wall-clock deadlines, including sleep time. Paused timers store remaining duration. Accepted durations are 1 through 86,400 seconds. Invalid commands leave state unchanged.

## Editor sessions

`OneGoalView(store:)` observes the shared store and retains one session in `@StateObject`. Both observations matter: the session publishes local edits, while the store publishes committed changes from any display. The store identity stays fixed for the lifetime of the view.

- `begin()` loads saved text and any saved duration. Repeated begin calls do not erase a live draft. `end()` discards the text draft, exits custom-duration mode, and clears focus intent without changing the store. Commands after end are ignored until begin.
- Save commits normalized text and ends the session. Blank Save and Done clear the saved text and timer.
- Starting or applying a timer commits the current draft. Pause, resume, restart, and clear do not commit it. Canceling or destroying an editor never rolls back those timer actions or stops the app monitor.
- A preset selects duration fields when no timer exists; otherwise it immediately applies the duration and draft. Canceling a duration edit restores the current shared duration; clearing outside that mode removes only the timer.
- Sessions keep independent drafts and focus requests. Another session's commit does not overwrite an open draft. Explicit saves are last-writer-wins; reopening loads the latest saved text.
- Focus requests are values, not native effects. SwiftUI bridges them to `@FocusState`; AppKit still controls key-window activation. Delayed initial focus checks task cancellation and session activity. Shared tab selection and cross-display editor protection remain shell responsibilities.

## Persistence

`OneGoalPersistence` loads, replaces, or clears one opaque `Data` snapshot. Replacement is immediately readable by the same backing store. Clearing is idempotent. Storage does not decode or repair bytes; the component owns that policy.

`UserDefaultsOneGoalPersistence` uses only `oneGoal.current`. Appearance preferences and the app's preferences domain do not change. Optional pause and completion fields keep older snapshots readable. Invalid JSON recovers to an empty goal and removes the snapshot. Invalid countdown values are removed from loaded state while preserving valid text.

Blank text or Done removes the text, countdown, and stored snapshot. Clearing a countdown preserves text. The current API does not report storage errors or guarantee that a write has reached disk. Do not claim durable exactly-once completion from it.

## Scheduling and lifecycle

`CountdownScheduling.schedule` takes a positive finite interval and a main-actor, Sendable callback. Registration never invokes the callback inline. The returned `AnyCancellable` must remain alive for ticks to continue. Canceling or releasing it on the main actor stops future delivery, including queued callbacks. Cancellation is idempotent.

The real adapter uses a repeating Foundation timer in the main run loop's common modes. A tick is a prompt to check the clock, not a promise of exact cadence. Tests use a manually advanced scheduler for deterministic transitions and also exercise the real adapter.

Construction does not start scheduling. Starting monitoring twice is idempotent. Pausing, clearing, finishing, stopping, or replacing a countdown cancels the current registration. Store teardown releases the token. Each registration captures a generation so even a misbehaving or already-queued old callback cannot finish a newer countdown.

## Completion and ordering

When monitoring finds a due countdown, the store persists its handled state, publishes the finished snapshot, cancels the registration, then calls `onCountdownFinished`. Repeated ticks cannot emit it again for that countdown. The app chooses the effect; component tests never play sound.

A countdown already expired when monitoring starts is marked finished silently. This also applies to restarting monitoring after an unmonitored interval. Pause/resume and reconstruction preserve the existing deadline policy.

This ordering prevents duplicate callback delivery in the tested process lifecycle. It cannot guarantee audible delivery across a crash between persistence and playback, or a failed durable write.

## Tests and limits

Run `scripts/verify.sh`, or `scripts/verify.sh --build` to also compile the unsigned app.

- `Packages/AnotchupFeatures/Tests/WorkingOnTests/OneGoalTests.swift`: state, decoding, duration, and real scheduler behavior.
- `Packages/AnotchupFeatures/Tests/WorkingOnTests/OneGoalContractTests.swift`: identical opaque-storage cases for memory and isolated UserDefaults adapters; identical scheduler lifecycle cases for manual and real run-loop adapters; real component behavior against both persistence implementations. Includes completion ordering, stale callbacks, shared subscribers, stop/restart, reconstruction, and teardown.
- `Packages/AnotchupFeatures/Tests/WorkingOnTests/OneGoalEditorSessionTests.swift`: editor lifecycle, validation, commit/cancel policy, and two-session/store composition against both persistence adapters. Checks one monitor, independent drafts/focus requests, reconstruction, and editor teardown without native effects.
- `Tests/OneGoalPresentationTests.swift`: deterministic caption/layout and media-policy checks, outside the feature module.
- `Tests/OneGoalRendererTests.swift`: offscreen native layout and sound loading without playback.
- `scripts/check-boundaries.py`: checks the package dependency graph and supplements Swift targets with source rules forbidding concrete persistence/scheduling and singleton access in feature logic. `Tests/test_boundaries.py` checks accepted and rejected inputs. Text checks are guardrails, not a Swift parser.

Subscriber and editor/store composition tests verify shared feature state, not actual SwiftUI environment propagation or physical multi-display focus. The app build checks production wiring compiles; runtime display, keyboard focus, and sound acceptance remain manual. Package display/navigation/lifetime composition has separate shell tests; actual native windows are not automated.
