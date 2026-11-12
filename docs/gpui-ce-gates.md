# GPUI-CE rewrite gates

Baseline: `193ead6`, branch `rewrite/gpui-ce`. The branch name is separate from `feat/rearch`; its ancestry deliberately retains the verified Swift implementation. The installed app is untouched. Shelf and Lottie are out of scope for the Rust replacement.

## Evidence so far

Completed without opening windows:

- Rust 1.99.1 builds GPUI-CE at `81742184cb1df090709257a5e4061eba44fa8e8a`, with one local macOS backend patch described below. `Cargo.lock` fixes transitive revisions too.
- Eight pure tests cover editor-only eligibility, both focus-transfer callback orders, independent displays, stale lifetime rejection, geometry, aspect-fill arithmetic and mirrored NV12 planes.
- The real Objective-C bridge compiles and its headless contracts pass: CoreVideo format/plane layout and copying, invalid dimensions, CF release, native path conversion and inside/outside samples of the Rust notch silhouette.
- Rust formatting, Clippy, build and headless checks pass without warnings. A [local block 0.1.6 patch](../rust/vendor/block/PATCH.md) fixes the invalid extern-static type and implicit C ABI declarations. Verification compiles that source with warnings denied and exercises actual native block copy/release and captured-resource lifetime.

These are build and contract results, not native window, Metal rendering, or performance acceptance. The owner's first graphical launch failed during CE popup creation. A later run opened below the menu bar, failing the placement gate. The first placement repair then caused an AppKit exception, leaving an idle process with no visible panel. These failures are recorded below. After the borderless-at-creation repair, the owner confirmed that the panel reaches the notch area. Initial placement passes on the tested setup. A later authorized native UI check passed hover focus, editor entry/exit, resize anchoring and stacking in a temporary full-screen Space, but failed passive-click focus and resized rendering. The resize defect was fixed on 2026-11-12. Passive-click focus passed on that day's code in both an ordinary desktop and a full-screen Space; the earlier failure is unexplained. Other displays remain unverified. A release build passes; Intel builds and minimum OS support have not been tested.

### First launch: popup initializer panic

The owner's `--show` run hit an Objective-C signature check before the anotchup adapter ran: CE declared `NSTrackingArea.initWithRect:options:owner:userInfo:` as returning void rather than an object. The exact panic was reproduced headlessly with the extracted production initializer. Correcting its return type and retaining the returned object makes that regression pass.

Only the macOS crate from the CE workspace is copied under `rust/vendor`, with its license, normalized manifest and [patch record](../rust/vendor/gpui_ce_macos/PATCH.md). Cargo verifies one patched backend and one pinned CE family. Runtime checks remain enabled, and the Cargo cache is untouched. The eight pure tests, Clippy, build and expanded headless checks pass. Another live run is still needed; this fix does not prove later startup or rendering stages.

### Placement failure: below the menu bar

The owner reported that the panel appeared below the menu bar. The pinned CE backend creates `Titled | FullSizeContentView` windows even with `titlebar: None`; hiding the title bar is not equivalent to the Swift reference's borderless panel. The initial bridge left that style and AppKit's frame constraint unchanged.

The current backend creates untitled popups as borderless, nonactivating panels from the start; the bridge rejects an unexpected style rather than changing it. Its per-instance subclass returns the requested rectangle from `constrainFrameRect:toScreen:` so AppKit does not push this overlay into the visible work area. Installation, showing and resizing anchor against the full screen frame. Ordinary windows and explicitly titled popups retain their previous style policy. GPUI's shared runtime classes are not swizzled.

Headless checks cover top-center coordinates on primary, negative-origin and vertically stacked screens at both probe sizes, plus the constraint function preserving the requested rectangle. The build and verification pass without warnings. These checks do not create a window or prove AppKit/compositor placement. The owner subsequently confirmed initial live placement after the repair described below; the remaining live checks are still open.

The probe prints `[placement]` on showing and resizing, with `target_top`, `window_top`, `content_top` and `gap`. In a passing top-edge placement, the three top coordinates should agree and `gap` should be zero. If it still appears displaced, include that line in the report. Correct window coordinates alone do not prove correct pixels or focus.

### Placement repair regression: running with no panel

The first repair changed `styleMask` after `object_setClass`. The owner then reported a running process with no visible panel and no terminal error. Sampling that process showed an idle AppKit event loop, not a deadlock. Its macOS unified log recorded `NSRangeException` with a stack through `NSWindow removeObserver:forKeyPath:context:`, `NSTitlebarView viewWillMoveToWindow:` and `NSWindow setStyleMask:`. The exception reason was redacted. AppKit caught the exception during launch and kept the event loop alive without completing our window setup.

The repair removes that runtime style mutation. The local CE backend now selects borderless/nonactivating style before the window initializer, so there is no title bar to tear down after the instance-class change. The shared production helper `popup_style.rs` is exercised by headless contracts: an untitled popup drops the old titled/full-size flags, while an explicitly titled popup preserves its requested controls. This is a style-policy regression test, not a reproduction of the full AppKit exception. Native window teardown and visual acceptance remain open.

Startup now prints `[startup]` stages before opening windows, configuring panels and completing each display probe. No `[placement]` or `probe ready` line means setup did not finish. The updated warning-free build and headless checks pass; verification does not modify or restart running probes.

On 2026-11-06, the owner restarted the updated probe and confirmed that it now reaches the notch area. This closes the reported startup regression and accepts initial placement on that setup. No coordinates, display inventory, focus, Spaces, resizing or teardown results were supplied.

### Authorized native UI check: focus and resizing failures

On 2026-11-06, the owner asked the assistant to perform the live checks. Existing Accessibility, event-posting and screen-capture access were available; no permission prompts were requested. A temporary Objective-C scratch application provided an editable field. Real CGEvents clicked the running probe and typed into the scratch field or the probe's explicit editor. Screenshots were restricted to the probe. No existing documents were edited. The scratch window and its temporary full-screen Space were closed, the probe's original size was restored, and the harness requested restoration of the prior application and pointer position.

Results on the current single-display setup:

- **Pass: hover.** The scratch field remained key and received the next character.
- **Fail: passive clicks.** Next frame, Mirror and Resize independently caused the scratch window to lose key status. The following character did not reach its field. The scratch application still remained the frontmost process, so checking only application activation would have missed this failure. Each case started with a freshly focused scratch field.
- **Pass: explicit editor.** Begin typing probe routed physical-key events to the probe, with the typed suffix visible in its screenshot and the scratch text unchanged. Escape, End and clicking the scratch field each restored typing to the scratch field; the probe returned to non-key mode.
- **Pass: frame anchoring only.** Window-server bounds changed from `(584, 0, 560, 320)` to `(524, 0, 680, 390)` and back. The top and horizontal center stayed fixed.
- **Fail: resized rendering.** After expansion, content shifted/clipped at the top and left unused space below. The defect remained after a two-second settling interval. Correct native frame bounds did not mean the GPUI view, drawable and mask resized together. The cause has not yet been isolated.
- **Pass: tested full-screen stacking.** In the scratch application's temporary full-screen Space, the probe remained on screen at its original coordinates and ahead of the scratch window in the WindowServer ordering. Returning to the original desktop preserved its frame and visibility. This does not cover arbitrary desktop-to-desktop switching, Mission Control, other apps' full-screen behavior or auto-hidden menu-bar interaction.

Two completed runs confirmed the focus failures and resized-content defect. The initial attempt was discarded after unexpected scratch-field input. A later harness attempt stopped because programmatic refocusing alone did not recover the field; completed runs used a real click to reset focus between cases. The initial Unicode-only event generator produced literal `a` characters in the GPUI raw-key probe; confirmation used matching physical key codes and verified the expected typed suffix. That first generator limitation is not evidence of an application typing bug.

Local diagnostic files: `/tmp/anotchup-ui-check/live.m`, `/tmp/anotchup-ui-check/results-confirmed.txt`, `/tmp/anotchup-ui-check/results-settled.txt` and probe-only PNGs in the same directory. These are temporary, coordinate-based test artifacts, not a portable contract suite. No production behavior was changed during this test request. Passive-click focus and resize rendering remain blockers.

### Resize rendering repair

On 2026-11-12 the resized-content defect was reproduced and fixed without sending any input events. `--show --steps resize,resize,resize` makes the probe toggle its own size on a timer, through the same code path as the Resize button. Captures were taken by window id.

Cause: the bridge called `setFrame:` from inside a GPUI update. AppKit resizes the view synchronously, so the backend's resize callback ran while the app was already borrowed. GPUI's handler uses a fallible borrow and drops the update, so the Metal drawable grew while GPUI kept laying out at the old viewport. The old frame was then stretched over the new drawable. Before the fix, no `[resize]` line was printed after a resize; the bounds observer never ran, so the mask was also stale.

Fix: `gate_resize` now dispatches the frame change to the next main-queue turn, as the backend's own `resize` does. It holds the view weakly and rechecks the gate class before use. Calling `Window::bounds_changed` directly from the handler is not an alternative: it re-enters the entity being updated and panics.

Evidence on the built-in display, three toggles: each resize now prints `[resize] gpui viewport=680x390` or `560x320` matching the native bounds, `gap` stays zero, and the captures at both sizes show the full layout, the top strip at the top edge and the mask's lower corners at the new bounds. The same cycle before the fix reproduced the clipped, shifted content. `verify.sh` passes.

Not covered: resizing by a real click on the Resize button after this fix, display scale changes, a second display, and repeated resizing under load. Blur and transparent shoulders at the new size were not inspected against a background.

### Input-free checks on 2026-11-12

Run on the built-in display, macOS 27.0.1, debug build, with no pointer, key or focus events. `--show --steps frame,mirror,resize,remove,quit` runs the button actions on a timer; `--step-ms` sets the interval. Begin typing is deliberately not scriptable because it takes keyboard focus. Captures were taken by window id and read pixel by pixel.

- **Fixed: aspect-fill crop.** `ObjectFit::Cover` enlarges the painted bounds beyond the element and does not clip. The 4:3 frame in the 210 by 130 box painted 27.5 points above and below it, over the neighbouring rows. The surface now sits in a fixed-size `overflow_hidden` box, whose content mask does the cropping. Any later camera view needs the same wrapper.
- **Fixed: fixture layout.** The video box was being shrunk by its flex row and the text column overflowed the panel. The box is now `flex_none` and the column can shrink.
- **Pass: colour, crop and mirror.** Eight captures across both sizes, three frame advances and both mirror states. About 5,500 samples per capture were compared with the generator, the cover-crop arithmetic and full-range BT.601 conversion, after converting to the display's P3 space. The worst channel error was 1 of 255. Samples within three source pixels of a colour boundary were skipped. Pixels just outside the box were background in every capture.
- **Pass: frame replacement.** 600 replacements at 50 ms intervals. Footprint stayed flat at 224 MB during the run and returned to 46 MB afterwards, against 33 MB for a fresh idle probe. `leaks` reported 410 leaks with no steps and 416 after both 100 and 600 steps, so nothing grows with frame count. The fixed set is rooted in an AppKit app-intents XPC connection, not in the bridge.
- **Pass: teardown.** Five scripted runs ending in Remove display probe or Quit, some after resizing, exited with status 0, no panic, no new crash report and no exception in the unified log. Editing-state teardown was not run, since it needs keyboard focus.
- **Pass: mask and transparency.** The shoulders, side gutters and lower corners have alpha 0 at both sizes, with the opaque edge starting at the same offsets after resizing. The green strip and gradient are clipped by the mask.
- **Idle redraw: found, then fixed below.** The backend's display link kept calling its frame callback while nothing changed.

Limits: one display at one scale. Captures show what the window server composited, not the panel against the hardware cutout. Blur was only checked by eye in the captures. The 224 MB figure under rapid replacement is unexplained. The startup log errors about app intents and a missing bundle identifier come from running an unbundled executable.

### Idle redraw repair

The pinned backend subscribes every visible window to its display's `CVDisplayLink` and never unsubscribes while the window is visible. Each vsync tick woke the main thread and ran GPUI's frame callback, which found nothing dirty and drew nothing. An idle probe measured about 247 context switches per second and 0.8% of one core. GPUI already has a wake hook for platforms that stop requesting frames, but this backend did not implement it.

Fix, in the vendored backend: `MacWindow::frame_waker` records demand and restarts a stopped link. After each tick, a window with no demand for 1.5 seconds stops its link. Demand is the window becoming dirty, a next-frame callback, or a pending forced render. The grace period covers GPUI's one second of sustained presentation after high-rate input. Occlusion, screen and key-status changes still restart the link as before. The policy lives in `frame_idle.rs` and is exercised by `--check-native`.

Evidence, same display and debug build, no input events:

- Idle for 10 seconds: 1.7 context switches per second and no measurable CPU time, against 247 and 9 centiseconds before.
- With 2.5 second steps, so the link was stopped before each one, all eight captures still matched the expected frame, crop and mirror, and the resize produced the new viewport. Timer-driven changes do restart the link.
- Six teardown runs, with the link both stopped and running, exited with status 0 and no panic, crash report or logged exception.
- 600 replacements at 50 ms intervals completed, then the process returned to no measurable CPU. The leak count was unchanged at 415.

A real click and hover while the link is stopped, a release build and an animation were checked later the same day; see the sections below. Occlusion and display changes while stopped were not tested.

### Owner-authorized input session on 2026-11-12

The owner handed over the pointer and keyboard for about 20 minutes. A scratch window with a text field observed its own key status while real CGEvents clicked the probe. Keys were sent only when the scratch field or the probe's editor was known to hold focus. Built-in display, macOS 27.0.1. The scripts are in `rust/live-checks/`.

- **Pass: passive clicks, ordinary desktop and full-screen Space.** Next frame, Mirror and Resize (both directions) each left the scratch field key, with no resign notification, and the next typed character arrived in the field. The probe log confirmed each action ran. The 2026-11-06 failure did not reproduce in either setting across four runs that day. Its cause is unknown, so this is a pass on the current code, not an explanation.
- **Pass: editing entry and exit.** Begin typing took key status and the typed characters reached the probe. Escape, Enter, the End button and a click on the scratch field each ended editing, returned key status to the scratch window and delivered the next character there. The same held in the full-screen Space for Escape and an outside click. An earlier run that day, where focus did not return, used a harness that reset focus programmatically; it did not recur.
- **Pass: teardown while editing.** Quit and Remove display probe, each clicked while the probe was key, exited with no crash report, and typing returned to the scratch field.
- **Pass: input while the display link is stopped.** After 2.5 idle seconds, hovering Next frame rendered its hover colour and a click rendered the new frame, in debug and release builds.
- **Pass: Spaces and stacking.** A screen-region capture matched the probe's own window capture on 100% of its opaque pixels on the desktop, in the scratch window's full-screen Space, with the auto-hidden menu bar revealed, after switching to the adjacent Space and back, during Mission Control and afterwards. The probe draws over the revealed menu bar and is not pushed down.

Harness defect, now guarded: the synthetic Control+arrow events used to switch Spaces left Control latched in the session, so later clicks became context-menu clicks and two later runs hung. No such click reached the probe or another application. The harness now releases modifiers after those events, refuses to start with one held and stops if one latches.

Not covered: another application's full-screen window, a second display, moving editing between displays, and the physical cutout.

### Further input-free checks on 2026-11-12

- **Pass: release build.** Builds in about 32 seconds to a 19.6 MB executable. Headless contracts, the eight-capture colour, crop and mirror comparison, and four teardown runs pass.
- **Pass: animation with the idle fix.** A scripted 600 ms repeating opacity pulse kept the display link running, at about 700 context switches per second and 0.7% of one core in release (1.7% in debug). After the pulse was removed the process returned to under 2 context switches per second and no measurable CPU.
- **Pass: resize under load.** 120 steps at 60 ms intervals mixing frame, mirror and resize delivered all 60 viewport changes, and the final capture matched the expected frame.
- **Memory footprint.** The roughly 220 MB figure is not caused by frame replacement. It is already present 0.6 seconds after launch, before any step, and stays while frames are being presented at any rate. About 144 MB of it is listed as reclaimable graphics memory. Once the window is idle the footprint is 39 to 46 MB. Which allocation owns it has not been traced.

Not done: blur has not been compared with the Swift app side by side. The deferred branch of the frame waker was exercised in the second input session.

### Second input session on 2026-11-12

Same setup, owner still away. One defect found and fixed.

- **Fixed: hover stuck after a fast exit.** When the pointer left a hovered button in one jump, the button kept its hover colour indefinitely, even after later moves elsewhere on screen. A slow glide out cleared it, because intermediate moves crossed the panel. GPUI does clear its pointer-inside flag on exit, but hit testing still uses the last move position, which the exit event does not update. The vendored backend now sends a move to the exit position before forwarding the exit. After the fix, jumps far away, just below the window, into the transparent gutter, and after the display link had stopped all cleared the hover; re-entering restored it and the next click worked.
- **Pass: transparent regions pass clicks through.** With the scratch window placed under the probe, clicks in the side gutters and below the rounded lower corner reached the scratch window. A click on the panel body did not.
- **Pass: right-click and scrolling.** Neither took key status from the scratch field; typing continued there.
- **Pass: click burst.** 30 clicks at about 70 ms spacing after the display link had stopped produced 30 actions and the correct final frame, with focus unchanged.
- **Pass: deferred frame wake.** With the direct restart temporarily disabled so every wake took the deferred branch, timed steps, a pulse, teardown, hover and a click all behaved the same. The temporary change was reverted.

### Text input and accessibility on 2026-11-12

The raw-key probe was replaced with GPUI-CE's own single-line `text_input` from `gpui_ce_elements`, at the same pinned revision. A click on the field makes the panel key, then the field takes focus. Enter and Escape are captured by the panel, which commits or cancels and gives the keyboard back. Real key events on a U.S. layout, owner away.

- **Pass: typing and editing.** Typed text arrived in order. Option+Left moved by word, Cmd+A selected all, Cmd+C then Cmd+V duplicated the text, Cmd+Z undid the paste and Backspace deleted. The owner's pasteboard was saved first and restored afterwards, with an unchanged checksum.
- **Pass: composition.** The dead keys Option+E then E produced é and Option+U then O produced ö, through a visible marked-text stage. An injected Unicode string (Japanese) was inserted intact, and a double-click selected one of its characters. This exercises the marked-text path only. No CJK input source is installed, so a real input method with a candidate window was not tested.
- **Pass: focus handover.** Clicking the field took key status. Enter, Escape and a click on the scratch window each returned typing to the scratch field, also in a full-screen Space. Clicking a passive button or empty panel area while editing kept the field focused and still ran the button. Quitting while typing left no crash report.
- **Pass: accessibility tree.** The system accessibility API sees the field as a text field. A button given a role and label appears as a button with that title, and an accessibility press on it ran the action and rendered the new frame without any pointer event.
- **Cost of a blinking caret.** While the field is focused the caret's 500 ms blink keeps the display link running, at about 313 context switches per second. It returns to about 4 after leaving the field. The link runs at display rate for a twice-a-second blink, so this is wasteful, but it only applies while editing.

Limits: elements get no accessibility role or label by default. A plain `div` with a click handler is invisible to assistive technology until the author adds both, so every control in the app would need them. The tree is built lazily and the first query after launch is incomplete. VoiceOver itself was not run. Selection by dragging, the candidate window of a real input method, and right-to-left text were not tested. The field has no "done editing" event; commit is the panel's own Enter handler.

### SwiftUI twin comparison on 2026-11-12

`rust/swiftui-twin/Twin.swift` is a SwiftUI copy of the probe: the same borderless nonactivating panel, level, size, placement, notch clip, content, timed steps and log lines, hosted in an `NSHostingView`. Both were release builds on the built-in display, measured with no input events by `live-checks/compare.sh` (two rounds, near-identical) and `live-checks/windowserver.sh` (ten rounds).

| Measure | GPUI-CE probe | SwiftUI twin |
|---|---|---|
| Executable size | 20.5 MB | 0.3 MB |
| Launch to panel ready, median of 5 | 132 ms | 105 ms |
| Idle CPU | none measurable | none measurable |
| Idle footprint | 33 MB | 16 MB |
| Footprint during a pulse or frame replacement | 221 to 224 MB | 17 MB |
| Pulse animation, app CPU | about 6.5% | about 5% |
| Pulse animation, context switches per second | about 670 | about 260 |
| Pulse animation, WindowServer CPU | 27 to 31% | 42 to 43% |
| Frames at 20 per second, app CPU | about 7% | about 6% |
| Frames at 20 per second, context switches per second | about 675 | about 50 |

WindowServer CPU with neither app running was 18 to 28% in the same rounds, from the rest of the desktop. So during the pulse the GPUI probe added roughly 8 points and the twin roughly 20. Dropping the twin's notch clip or its system material did not reduce that. Adding app and WindowServer cost together, the pulse is cheaper overall in GPUI and the twin is cheaper inside its own process.

Reading: idle cost is equal, which is the state a notch app is in almost all the time, and it needed the display-link patch to get there. SwiftUI uses far less memory and wakes the process far less while something is moving. GPUI's own process costs slightly more, but it hands the compositor one finished layer, which is cheaper for the system during animation.

Limits. This is a small fixture, not the app: the Swift app's real cost is mostly media, calendar and HUD work that neither twin includes. WindowServer figures are shared with the whole desktop and noisy; only the consistent gap across rounds is meaningful. The twin shows frames as layer contents and builds each frame in Swift on the main thread, which is part of its app CPU in the frame test; its video colours differ from the expected values by up to 33 of 255, where the GPUI probe is within 1. Text editing cost, energy on battery and the lock screen were not compared. The executable size gap is mostly SwiftUI being a system framework.

## First owner check: can it sit around the physical notch?

This is the first live gate, before inspecting video or blur. No software can draw on the physical camera cutout. The goal is a window that reaches the screen's top edge and surrounds or extends below that cutout, rather than being pushed underneath the menu-bar safe area.

Quit the installed notch app yourself so the two panels cannot be confused. From `rust/`, run:

```sh
./verify.sh
cargo run --locked --features gui -- --show
```

The probe requests a 560 by 320 point expanded diagnostic panel at the full-screen top center of each connected display. It deliberately does not use the work-area/visible-frame origin. It is not a finished, compact black notch UI, does not measure the hardware notch width, and does not implement hover expansion. The native Resize action also anchors to the full NSScreen frame.

Check in this order on the built-in notched display:

1. **Placement:** the upper edge touches the physical top edge, centered around the cutout. Content behind the physical cutout is expected to be occluded; the panel should not be wholly displaced below the menu bar. A gap or sideways offset is a failure to report.
2. **Stacking:** bring another application forward and move its window underneath. The probe should stay visible rather than hiding or becoming an ordinary background window.
3. **Spaces:** switch to another desktop, then to a full-screen application. The probe should remain attached at the top. Also test revealing an auto-hidden menu bar. Disappearance, relocation or being pushed down is a failure; do not change system settings to conceal it.
4. **Passive focus:** click a text field in another app and type. Hovering the probe and clicking its non-editor controls should not redirect keyboard input. Begin typing is the deliberate exception. Escape or clicking back into the other app should return typing there.
5. **Resize:** toggle both sizes; the top-center anchor must not move. Then check transparent shoulders, video frames and mirroring if placement passes.

Use Quit or Ctrl+C to remove the probe. Report pass/fail for placement, stacking, Spaces and focus, including the macOS version and which display failed. A photo is useful for physical-cutout alignment; screenshots alone cannot show the hardware boundary reliably. No screenshot or permission grant is required.

The agent can test code, geometry and headless ABI/resource contracts. Actual compositor, display-cutout and window-focus acceptance needs this live observation. Initial placement is owner-confirmed. The authorized native UI results above cover a subset of these checks and record two failures; untested cases remain open.

## Gate 1: native panel and focus

Implementation: a hidden, unfocused CE popup, then a guarded per-instance subclass with editor-only `canBecomeKeyWindow` and unconditional non-main behavior. Preserve CE's self-delegate and inherited state. Missing native state denies key eligibility. Ending editing explicitly resigns. A Rust lifetime token rejects callbacks for removed/recreated owners.

Manual acceptance checklist; see the live results above for the tested subset:

- Opening the probe leaves the previously active application and text field focused.
- Non-editor clicks and hover do not steal typing from another app.
- Begin permits typing; End, Return, Escape and clicking another app end editing without leaving an active key panel.
- Moving editing between two displays works in both native callback orders.
- Closing an editing or non-editing window does not crash, leak observers or access stale handles. Quit removes all panels.
- Public window-level/Spaces flags behave as intended in full-screen apps and across Spaces. This does not establish lock-screen/private SkyLight parity.

Fallback if instance-subclass safety fails: normalize and pin a local copy of only `gpui_ce_macos`, apply an explicit Cargo patch, and test the dependency graph. Do not modify the global Cargo cache. See [council rationale](gpui-ce-council.md).

## Gate 2: clipping and composition

Implementation: the Rust port of the current concave notch path becomes a `CAShapeLayer` mask on the GPUI native view's layer. Child content deliberately overflows the shoulders. CE's own content/backdrop blur APIs are included as fixtures; the earlier upstream-GPUI audit did not describe this CE implementation.

Manual acceptance checklist; resized rendering was repaired on 2026-11-12, the rest is open:

- The gradient, green strip, text and rendered surfaces are clipped together, with genuinely transparent corners, not black rectangles.
- Resize and display scale changes keep the mask aligned without inversion, seams, stale bounds or clipping regressions.
- Content blur and backdrop blur display correctly under the native mask. A blur API compiling is not visual equivalence with SwiftUI.
- Rendering idle content does not keep redrawing unexpectedly. The idle display link was stopped on 2026-11-12; see the repair record. No battery or comparative claim against the Swift app is made.

## Gate 3: camera rendering route

Implementation: synthetic full-range, bi-planar 420 CoreVideo buffers exercise CE's required Surface format. `ObjectFit::Cover` selects cropping. CPU-generated mirror variants preserve chroma-pair ordering. Frames change only on explicit button clicks, so this is not a stream-throughput test.

Manual acceptance. The 2026-11-12 input-free checks cover the first three on one display and scale; the camera mask is still open:

- Metal initializes and displays correct, changing luminance/chroma content without panic or format errors.
- Aspect-fill crop and horizontal mirroring are visually correct at both panel sizes and display scales.
- Replacing and dropping buffers, removing windows and quitting release resources safely.
- Choose and validate a separate circular/rounded camera mask. CE Surface still has a corner-radius TODO; the fixture deliberately does not hide this gap.

Only after the synthetic gate: add a separately enabled AVFoundation adapter with permission, disconnect, cancellation and shutdown contracts. No real camera session exists in this experiment.

## Before feature migration

Do not treat this scaffold as acceptance of all three gates. Next work is to run the explicit synthetic experiment with the owner, record failures and fix the native/rendering route. Text input, dead-key composition and the accessibility tree were covered on 2026-11-12. Still to cover: a real CJK input method, VoiceOver, display hotplug, lock policy, status item and remaining macOS adapters. Port Working on first once the shell and input route are sound. Retain behavioral contracts from the Swift reference rather than carrying over Shelf or Lottie.

The [source audit](gpui-feasibility-audit.md) remains historical evidence for a different upstream GPUI revision. The [CE council record](gpui-ce-council.md) identifies what changed and what is still uncertain.
