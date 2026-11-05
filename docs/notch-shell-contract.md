# Notch shell contract

This is the first shell extraction, not a complete window/session architecture. `NotchShell` lives in `Packages/AnotchupFeatures`, depends only on Foundation, and has no dependency on Working on or native UI services.

## Ownership

Each `AnotchupViewModel` owns two separate `NotchDelayedActionSession` values: one for hover and one for shortcut auto-close. `ContentView` owns the hover task; the view model owns the shortcut task. Each supplies a fresh `NotchInteractionState` at delivery. The package decides whether an effect is allowed; the app applies animations and window changes. Do not copy a live session between displays.

Shared tab selection stays in `AnotchupViewCoordinator`. Native editor-focus transfer, window creation, screen geometry, camera authorization, and media refresh still live in the app. Nothing in this slice changes their shared/per-display semantics.

## Decisions

- Every close respects sharing and editor protection. A deliberate editor dismissal first releases editor protection. General closes do not acquire the hover-specific battery or pointer guards.
- Hover-open requires a closed notch, hover still active, no goal-control hover, no visible preview, and hover-open enabled. Both request and delivery read those conditions.
- Hover-exit ends visual hover even when the notch cannot close. Closing additionally requires an open notch, no battery popover, and no sharing/editor protection.
- After sharing ends or the battery popover closes, delayed close also requires hover to be inactive at delivery.
- Open waits for the configured minimum hover duration. Exit and protection-release close retain the existing 100 ms delay. First-launch suppression and haptics remain app-side.
- Shortcut-open schedules one close after three seconds. Delivery requires an open notch without sharing/editor protection, but deliberately ignores pointer and battery hover guards. A blocked close is consumed, not retried after editing ends.

## Delayed work

`schedule(_:)` replaces the pending request and returns an opaque ticket. `fire(_:state:)` consumes a matching ticket once and returns an effect or no effect. A blocked request is still consumed. A replaced, canceled, foreign, or previous-lifetime ticket cannot change state or consume a newer request.

`cancel()` is idempotent and permits later scheduling. Pointer reentry and goal-control hover cancel only the hover lane. Explicit open, successful close, shortcut toggle, and teardown invalidate both lanes synchronously. The shortcut task is canceled too. Hover tasks remain view-owned and check cancellation after sleeping; tickets reject deliveries invalidated by model transitions.

App wiring cancels delayed interactions on root disappearance, lock/unlock, display reassignment/removal, window cleanup, and termination. Removed view models release subscriptions; the drop-target subscription captures its owner weakly. Shortcut routing rejects missing display owners rather than scheduling work on an invisible fallback model.

View disappearance also cancels the existing drag-debounce and timer-width tasks and clears local hover flags. Those tasks' policies have not moved into the package.

The extraction adds deliberate safety changes: pending hover-open rechecks the preference, and reopening/teardown invalidates older delayed decisions. A stale close cannot close a newly opened notch. Opening outside the pointer clears lingering visual hover. Shortcut timers are now display-local: opening display B no longer cancels display A's timer. Hover reentry still does not cancel shortcut auto-close.

## Verification and limits

The two files in `Packages/AnotchupFeatures/Tests/NotchShellTests` import only the public module. Nine hover tests cover decision matrices, one-shot delivery, replacement, cancellation, current-state protection, recreation, and display isolation. Six shortcut tests cover the close matrix, consumed protection, stale callbacks after reopening, independent deadlines, separate hover/shortcut lanes, and recreation. No real delays, windows, camera/media services, or desktop interaction are needed.

These are component contract tests. They do not prove SwiftUI lifecycle callback ordering or native focus transfer. `scripts/verify.sh --build` checks package boundaries, these tests, the existing Working on suites, and production app wiring.

Still outside the automated contracts: native task timing and lifecycle delivery, drag/drop decisions, shared preview timing, tab-reset policy, actual lock/unlock/display removal, and window/focus composition. Host cancellation calls compile but are not runtime-tested by the pure session cases. Manual acceptance should cover fast exit/reentry, reopening before a shortcut deadline, shortcut use on two displays, editor/battery/share protection, display removal/lock transitions, and focus transfer. No automated check launches the app to perform those actions.
