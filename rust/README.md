# GPUI-CE technical gates

A separate Rust executable for the `rewrite/gpui-ce` branch, based on `193ead6`. It is not the replacement app yet. The Swift app remains the behavioral reference. Shelf and Lottie are excluded from the rewrite, not deleted from that reference.

## Build and verify

Requires the Rust 1.99.1 toolchain, Python 3, and Xcode's macOS SDK/Metal tools for the graphical build. GPUI-CE is pinned to `81742184cb1df090709257a5e4061eba44fa8e8a` in `Cargo.toml` and `Cargo.lock`, with a [local macOS backend patch](vendor/gpui_ce_macos/PATCH.md) for a popup initializer return-type bug. Run commands from this directory so a rustup installation sees `rust-toolchain.toml`.

```bash
./verify.sh
```

This runs eight pure Rust tests, checks the CE dependency pin, runs Clippy, builds the actual GPUI-CE executable on macOS, and runs headless CoreVideo/CoreGraphics contracts. It never creates a window or capture session. The default Cargo feature set excludes the graphical executable.

The headless native checks cover real block copy/release and captured-resource lifetime, the production popup style policy and tracking-area initializer, real full-range NV12 allocation, stride-aware plane copies, ownership release, invalid dimensions, and the Rust notch silhouette converted into a native CGPath. They do not initialize the Metal renderer or establish compositor correctness.

## Explicit graphical experiment

This command opens synthetic panels at the top of connected displays. Do not run it as part of ordinary verification. It can overlap the installed notch app. It does not stop or modify that app.

```bash
cargo run --locked --features gui -- --show
```

**Start with physical placement, not video.** On the built-in display, check that the large diagnostic panel sits flush with the screen's top edge, centered around the hardware cutout, rather than below the menu bar. Then check visibility over other apps, across Spaces and in full-screen, followed by passive focus. The [owner checklist](../docs/gpui-ce-gates.md#first-owner-check-can-it-sit-around-the-physical-notch) gives pass/fail conditions. Initial placement is confirmed. The live checks found failures in passive-click focus and resized rendering; hover, explicit editor entry/exit, frame anchoring and the tested full-screen stacking passed. Resized rendering has since been fixed. Passive-click focus did not reproduce in a later run and is unresolved. See the gate record for limits and remaining checks. The hardware cutout itself cannot display pixels.

- Creates a borderless, nonactivating popup while hidden and unfocused, installs a guarded panel subclass and a native notch mask, then shows without explicit activation. It no longer changes the window style after subclassing.
- Prints `[startup]` stages and `[placement]` coordinates. A process that stays alive without `probe ready` has not completed setup; AppKit exceptions may appear only in the macOS unified log.
- Begin typing probe permits key status. End, Enter, Escape, and native focus loss end editing. This is a raw-key probe, not a text editor: no selection, composition, IME, clipboard, or accessibility parity is claimed.
- Next frame changes a synthetic asymmetric NV12 frame; Mirror reverses luminance pixels and chroma pairs before upload. There is no camera, repeating frame producer, or audio.
- Resize changes the panel dimensions and rebuilds the outer mask. The native frame change is deferred to the next main-queue turn, so GPUI receives the new viewport. `--show --resize-cycle` toggles the size three times on a timer, for checking this without input events. The green strip and gradient deliberately extend into the concave shoulders.
- Remove display probe closes that window. Quit exits the process. Display enumeration happens at launch; hotplug reconciliation is not implemented.
- The camera fixture intentionally has square corners. An outer notch mask does not solve the independent camera crop.

No user preferences, persistence migration, private SkyLight API, system helper, permission request, status item, login item, or installed-app integration is included.

## Files and boundaries

- `src/lib.rs`: display-lifetime tokens, editor/focus policy, notch geometry and synthetic image planes.
- `src/main.rs`: GPUI composition and manual controls. GPUI owns NSApplication and its run loop.
- `src/native.rs`: borrowed native handles and owned CoreVideo buffer wrappers. Handles never escape a live GPUI callback.
- `native/gate.m`: per-instance Objective-C subclass, key policy, native mask and pixel-buffer construction. It preserves the GPUI delegate and inherited instance layout; there is no global method swizzle or Cargo-cache patch.

The subclass accepts only the pinned CE `GPUIPanel` class, while hidden on the main thread, and verifies equal instance size. It is experimental: KVO/isa changes, AppKit behavior, destruction and renderer-layer interactions still require live validation. See the [council decision](../docs/gpui-ce-council.md) and [gate checklist](../docs/gpui-ce-gates.md).

The inherited project license and notices remain in force. The notch path credits the original Swift implementation. Dependency licensing, distribution, signing, minimum macOS support and performance are not cleared by this build. The [local block 0.1.6 patch](vendor/block/PATCH.md) fixes the dependency warning without suppressing it. Verification checks the patched source with warnings denied, and the current build and headless checks emit no warnings.
