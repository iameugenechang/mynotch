# Notch shell contract

`NotchShell` owns interaction policy, shared navigation, geometry arithmetic, and display-resource lifetimes. It lives in `Packages/AnotchupFeatures`, imports Foundation and Combine (plus CoreGraphics value types only in `NotchGeometry.swift`), and has no dependency on Working on or native UI services. `NotchShellAdapters` implements one-shot scheduling and notification registration ownership.

## Ownership

Each main-actor `AnotchupViewModel` owns one `NotchInteractionLifetime`. That owner holds separate hover, shortcut, drag, and resize lanes, including their policy tickets, cancellation tokens, state readers, and effect callbacks. App composition injects `TaskNotchDelayScheduler`; previews can use the view model's convenience initializer.

`ContentView` supplies hover state and applies animation/window effects. The view model supplies shortcut state and effects. Both read current protection at delivery, not when scheduling. Callbacks capture the model weakly; hover callbacks capture the required SwiftUI state bindings instead of the whole view. State readers must be side-effect-free. Effect callbacks may cancel or schedule more work.

The coordinator owns one `NotchNavigation` for shared tab selection and editor-focus requests, plus a lifetime owner for compact/expanded previews. `NotchDisplayLifecycle` reconciles selected display IDs: unchanged IDs retain their resources, removed IDs are destroyed before replacements are created, and stop is terminal. App composition supplies window/model creation and destruction. Each resource owns its native observer token.

Geometry arithmetic is pure; screen measurement and animations stay native. `NotchViewDependencies` injects navigation, visibility, sharing/Shelf reads, media refresh, and the user camera command. Constructing a shell model does not request camera permission or construct a media provider. The app's notification adapter retains registrations, defers delivery to the main actor, and rejects queued callbacks after stop or owner release. Callbacks must capture their owner weakly.

## Decisions

- Every close respects sharing and editor protection. A deliberate editor dismissal first releases editor protection. General closes do not acquire the hover-specific battery or pointer guards.
- Hover-open requires a closed notch, hover still active, no goal-control hover, no visible preview, and hover-open enabled. Both request and delivery read those conditions.
- Hover-exit ends visual hover even when the notch cannot close. Closing additionally requires an open notch, no battery popover, and no sharing/editor protection.
- After sharing ends or the battery popover closes, delayed close also requires hover to be inactive at delivery.
- Open waits for the configured minimum hover duration. Exit and protection-release close retain the existing 100 ms delay. First-launch suppression and haptics remain app-side.
- Shortcut-open schedules one close after three seconds. Delivery requires an open notch without sharing/editor protection, but deliberately ignores pointer and battery hover guards. A blocked close is consumed, not retried after editing ends.

## Scheduling contract

`NotchDelayScheduling.schedule(after:_:)` returns an `AnyCancellable` for one pending main-actor callback:

- Delivery is never inline, including zero-delay requests. Negative delays behave as zero.
- Retaining the token permits one delivery. Canceling or releasing it suppresses pending delivery; cancellation is idempotent and affects only that token.
- No exact delivery time or order across independent tokens is promised. Cancellation cannot undo an effect that has already run.

`TaskNotchDelayScheduler` sleeps in a main-actor task, returns on cancellation, and checks cancellation again before invoking the callback. Tests use the same contract cases for this adapter and a manual scheduler. The manual scheduler also has an adversarial stale-delivery hook to test the owner's defenses independently of adapter cancellation.

## Delayed work and teardown

`NotchDelayedActionSession.schedule(_:)` replaces a pending decision and returns an opaque ticket. `fire(_:state:)` consumes a matching ticket once and returns an effect or no effect. A blocked request is still consumed. A replaced, canceled, foreign, or previous-lifetime ticket cannot consume newer work.

`NotchInteractionLifetime` couples these tickets to scheduler registrations. Scheduling replaces only the corresponding lane. `cancel(_:)` and `cancelAll()` release callbacks and cancel tokens, but permit later scheduling. `invalidate()` is terminal and rejects future work. Releasing the owner releases its tokens. Scheduler callbacks hold the owner weakly.

Delivery removes the pending entry before reading state or applying effects. A callback can therefore schedule another action without the completed action erasing it. Stale delivery neither reads host state nor applies effects.

Pointer reentry and goal-control hover cancel only the hover lane. Explicit open, successful close, and shortcut toggle cancel all display lanes synchronously. App wiring also cancels on root disappearance, lock/unlock, display reassignment, and window cleanup. Removed view models and termination permanently invalidate their owners and cancel subscriptions. A retained callback cannot restart a removed owner's delayed work. Shortcut routing rejects missing display owners rather than using an invisible fallback model.

View disappearance cancels drag/resize registrations and clears local hover flags. Drag exit waits 500 ms, consumes a recorded drop without closing, and otherwise respects editor/sharing protection. Resize waits 700 ms and resumes width tracking only if closed without a preview. Compact and expanded preview hide requests use independent lanes; replaced or canceled callbacks cannot hide newer content. Lock/unlock and termination cancel previews.

The earlier extraction added deliberate safety changes: pending hover-open rechecks the preference; reopening invalidates older decisions; opening outside the pointer clears lingering visual hover. Shortcut timers are display-local: opening display B does not cancel display A's timer. Hover reentry does not cancel shortcut auto-close. The lifetime extraction preserves these rules.

## Verification and limits

Tests in `Packages/AnotchupFeatures/Tests/NotchShellTests` use public imports, without `@testable`:

- Nine hover and six shortcut tests cover decision matrices, tickets, delivery-time protection, replacement, recreation, and display isolation.
- Eight lifetime tests cover real cancellation-token ownership, independent lanes/displays, terminal removal, recreation, queued stale callbacks, reentrant effects, callback release, owner release, and composition with the real task adapter.
- Two scheduler tests run shared conformance cases against the manual and real adapters, including deferred delivery, one-shot behavior, token cancellation/release, zero/negative delays, and independence.

Three navigation cases cover close-default precedence, transfer in either native callback order, and removal/canceled requests. Three presentation cases cover drag, resize, preview lane replacement, and teardown.

Four display/geometry cases and two real notification-adapter cases cover reconciliation, selection/lock policy, navigation/lifetime composition, notification delivery, and observer teardown. These 37 shell cases require no windows, camera/media services, or desktop interaction. Most use manual time; the real-adapter cases use bounded asynchronous waits. They do not prove exact timing, SwiftUI callback ordering, or native focus transfer. The normal verification suite also compiles a separate optimized AppKit geometry client to guard cross-module Release compilation. `scripts/verify.sh --build` checks Debug app compilation; `--release-build` checks Release. See [the compiler-crash investigation](release-compiler-crash.md).

Still outside the automated contracts: OS-generated lifecycle events, geometry measurement, actual lock/unlock/display removal, and native window/focus composition. Tests exercise the production notification adapter and package composition, not the app delegate or SwiftUI trees. Manual acceptance should cover fast exit/reentry, reopening before a shortcut deadline, shortcut use on two displays, editor/battery/share protection, display removal/lock transitions, and focus transfer. No automated check launches the app to perform those actions.
