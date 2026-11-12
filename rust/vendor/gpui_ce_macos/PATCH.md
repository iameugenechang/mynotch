# Local GPUI-CE macOS patch

Source: https://github.com/gpui-ce/gpui-ce/tree/81742184cb1df090709257a5e4061eba44fa8e8a/crates/gpui_macos

Copied from that exact Git checkout on 2026-11-05. The original `LICENSE-APACHE` and source files are retained. Only this crate is copied; sibling crates remain canonical Git dependencies at the same revision. The application manifest applies this directory through `[patch."https://github.com/gpui-ce/gpui-ce"]`. No global Cargo-cache edits or disabled Objective-C checks are involved.

## Changes

- `Cargo.toml`: expand inherited package fields, workspace dependency declarations and lints into a standalone manifest. Preserve aliases, version requirements, features, optional/default-feature flags and target/dev dependencies. Convert sibling dependencies, including the fonts dev-dependency, to the pinned Git source.
- `src/window.rs`: extract popup tracking-area construction into `src/popup_tracking.rs`; add the resulting retained area to the view. AppKit retains it, then Rust drops the local owned reference.
- `src/popup_tracking.rs`: declare `initWithRect:options:owner:userInfo:` as returning an object pointer, not `()`. Wrap the initializer's returned pointer in `Retained`, rather than assuming it equals the allocated pointer. Rectangle and tracking options are unchanged.

This fixes the debug runtime panic:

```text
invalid message send to -[NSTrackingArea initWithRect:options:owner:userInfo:]: expected return to have type code '@', but found 'v'
```

The initializer change is independent of anotchup's per-instance key-policy subclass. It happens earlier, while GPUI creates a popup.

### Untitled popup style

`src/window.rs` also uses `src/popup_style.rs` to select a popup's style before native window initialization. Untitled popups start as `Borderless | NonactivatingPanel`, rather than `Titled | FullSizeContentView | NonactivatingPanel`. Explicitly titled popups retain their original flags plus `NonactivatingPanel`. Other window kinds are unchanged. Anchored popups remain rejected by the platform before this code runs.

The original titled probe appeared below the menu bar. Changing its style to borderless after anotchup's per-instance class replacement caused an AppKit `NSRangeException` during title-bar KVO observer removal. The running process's unified log confirmed the exception stack; the terminal showed no error. Creating the panel borderless avoids that teardown path. The bridge now validates the style instead of mutating it. No method swizzle or new application delegate is introduced.

### Idle display link

Upstream keeps a visible window subscribed to its display link indefinitely, so an unchanged window wakes the main thread on every vsync tick. `src/window.rs` now implements `PlatformWindow::frame_waker`, which GPUI calls when a window becomes dirty or gains next-frame callbacks. `step` stops the link once `src/frame_idle.rs` reports 1.5 seconds without demand, and the waker restarts it. Existing restarts on occlusion, screen and key-status changes are unchanged, and they also re-arm the idle timer.

The waker holds the window state weakly. It restarts the link directly when it can take the state lock, and otherwise defers to the foreground executor, because GPUI may wake during a backend call that already holds that lock. This applies to every window kind, not only popups.

### Pointer position on exit

Upstream forwards `mouseExited:` without updating the pointer position GPUI uses for hit testing. An element under the pointer's last reported position stays hovered after the pointer leaves the window in one jump. `handle_view_event` in `src/window.rs` now sends a `MouseMove` to the exit position, with the exit's button and modifier state, before forwarding the exit. This applies to every window kind. It is covered only by the live runs in the gate record.

## Regression evidence

`rust/src/native.rs` compiles the exact `popup_tracking.rs` used by this backend and calls it on the main thread with a live NSObject owner. It checks the resulting owner, options and rectangle and releases the objects. No NSApplication or window is created.

With the original void-return declaration, `--check-native` reproduced the exact panic and exited 101. With the object-return fix, the same check passes. The full `rust/verify.sh` also passes and asserts that Cargo resolves exactly one macOS backend at this local path. This does not establish that the rest of window creation or live rendering works.

`rust/src/native.rs` also compiles the exact production `popup_style.rs`. Its headless contracts require untitled popups to start borderless and explicitly titled popups to preserve controls and resize policy. The passing style test does not create a window or reproduce the KVO exception. The updated build and headless checks pass without warnings; live placement and teardown still require acceptance.

`rust/src/native.rs` compiles the exact `frame_idle.rs` and checks the grace period, demand resetting it, a restarted link and a backwards clock. Stopping and restarting a live link is covered only by the live runs in the gate record.

Remove each patch when adopting an upstream revision with the corresponding fix, retaining the regression tests against that revision's production code. Do not replace this with Release mode or a disabled message-signature check.
