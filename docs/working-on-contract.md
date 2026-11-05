# Working on component contract

## Ownership and inputs

`OneGoalStore` owns the saved `OneGoal` snapshot and countdown transitions. All access is on the main actor. Commands save text, start/pause/resume/restart/clear a countdown, complete the goal, and start/stop monitoring. Consumers observe read-only published state. The editor's uncommitted draft and focus remain in the UI for now.

`AppDelegate` constructs one store and injects that instance into every display's SwiftUI tree. It starts monitoring at app launch, connects completion to the sound player, and stops monitoring at termination. Views do not create stores or discover one through a singleton. Previews explicitly supply an isolated preferences instance.

Time is an injected `() -> Date`. Running timers use wall-clock deadlines, including sleep time. Paused timers store remaining duration. Accepted durations are 1 through 86,400 seconds. Invalid commands leave state unchanged.

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

- `Tests/OneGoalTests.swift`: existing state, decoding, duration, layout, and media-policy behavior.
- `Tests/OneGoalContractTests.swift`: identical opaque-storage cases for memory and isolated UserDefaults adapters; identical scheduler lifecycle cases for manual and real run-loop adapters; real component behavior against both persistence implementations. Includes completion ordering, stale callbacks, shared subscribers, stop/restart, reconstruction, and teardown.
- `Tests/OneGoalRendererTests.swift`: offscreen native layout and sound loading without playback.
- `scripts/check-boundaries.py`: temporary source-level rules keep concrete persistence/scheduling and singleton access out of the component. This is a text check, not a substitute for Swift target boundaries.

Two subscribers verify shared feature state, not actual SwiftUI environment propagation or physical multi-display focus. The app build checks production wiring compiles; runtime display, editor, and sound acceptance remain manual. A dedicated composition test target, package boundaries, and editor-session extraction are still pending.
