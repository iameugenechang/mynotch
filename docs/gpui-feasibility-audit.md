# GPUI replacement audit

Date: 2026-11-05.

## Verdict

A SwiftUI-free version of anotchup is technically plausible using GPUI, macOS adapters, and some custom rendering work. I found no product requirement that inherently requires SwiftUI.

That is not the same as saying stock GPUI already reproduces this app. It does not provide direct equivalents for several behaviors we currently get from SwiftUI and AppKit together. Exact visual and native-window parity remains unproven, especially for notch clipping, camera composition, nonactivating editor windows, and rich drag/drop.

My recommendation is to treat GPUI as a viable frontend candidate, conditional on the specific acceptance checks below. This judgment excludes rewrite cost. It concerns what the finished implementation would need to support and maintain.

Three distinct questions have different answers:

- **Can we replace our SwiftUI views?** Yes, with reimplemented GPUI views, custom elements, and native bridges where needed.
- **Can stock GPUI alone provide everything those views currently do?** No, not on the source evidence examined.
- **Can we promise identical behavior, appearance, accessibility, and efficiency now?** No. Source inspection cannot establish that.

## Scope and evidence

App baseline: `193ead6f1ae9015213f9fca86a3f6e101bc1f7f2`.

GPUI source baseline: Zed commit `4a6121bb0f10c6e8037b741b7dc0a4cd639ae289`. The audited code includes `gpui`, `gpui_macos`, `gpui_apple`, examples, and accessibility documentation. Claims here concern this snapshot, not every published GPUI version.

Optional community controls: `longbridge/gpui-kit`, formerly reached through the `gpui-component` repository URL, commit `b2aaa3e5f9a387dea74981586bfca33e7e08420d`. Its workspace uses version `0.9.0` and pins `gpui-pre` to `=0.3.11`. That is **not a verified compatible pairing** with the Zed commit above. A real implementation needs one consistent, tested dependency set.

Method:

- Inventoried all app Swift files and package source files, then all SwiftUI imports and hosting/representable uses.
- Classified all 72 app files matching SwiftUI imports or hosting/representable patterns. Some are models or incidental imports, not UI screens. The appendix records each one.
- Read the main notch, Working on, music, camera, Calendar, Shelf, settings, onboarding, and native view bridge implementations. Checked supporting controls, effects, lifecycle code, and call sites for dormant views.
- Compared those requirements with pinned GPUI platform and rendering implementation, not just marketing documentation.
- Searched for missing equivalents within the inspected core/platform sources. Absence claims below mean no supported equivalent was found there, not that nobody could implement one or that no external project exists.

This was a static feasibility audit. No GPUI application was compiled or run, no prototype or benchmark was performed, and no camera, permission dialog, drag session, or VoiceOver session was exercised. Only this report was added to the app repository.

## Replacement map

"Direct" means supported building blocks exist, not that SwiftUI source translates mechanically. "Custom" means application-owned behavior or rendering. "Native" means a macOS bridge remains. "Gate" means the exact behavior needs a proof before claiming parity.

| Current area | GPUI route | Assessment |
| --- | --- | --- |
| Rows, columns, stacks, spacing, overlays, lists, scrolling | GPUI elements, flex/grid layout, scroll handles | Direct |
| Ordinary buttons, toggles, radio/select controls, sliders, dialogs | Build from core elements or use community controls | Direct/custom; community controls are not AppKit controls |
| Settings sidebar and forms | GPUI layout plus controls | Direct/custom |
| Working on label, timer digits, progress ring | Text, paths, explicit state updates | Direct/custom |
| Working on editor | Input component or `EntityInputHandler`, focus handles, commands | Custom; native key-window and IME acceptance gate |
| Calendar list and reminder controls | Lists, buttons/toggles, date formatting adapter | Direct/custom |
| Calendar date wheel | Horizontal scrolling, measured item positions, snap/selection policy | Custom; preserve momentum and haptics |
| Media title, artist, lyrics, time, controls | Text, images, progress controls, scheduled updates | Direct/custom |
| Animated four-bar visualizer | Draw and animate four bars | Direct/custom; this is not an audio FFT renderer |
| Shelf grid/list and selection | Images, labels, scrolling, selection model | Direct/custom |
| Settings music-slot reorder | Typed internal GPUI drag/drop | Direct/custom; distinct from external system drags |
| File-only external drag/drop | GPUI macOS external drag APIs | Partial direct coverage |
| Full Shelf drops, promises, URLs, text, images | AppKit pasteboard/item-provider bridge | Native gate |
| Sharing picker and Quick Look | Existing macOS services with native anchor/lifecycle | Native gate; no SwiftUI requirement |
| Camera preview | Native preview layer bridge or `CVPixelBuffer` surface pipeline | Native/custom rendering gate |
| Notch silhouette and clipping all descendants | Draw shape; separately solve group clipping and alpha | Custom rendering gate |
| Album-art blur, blur transitions, gradient masks, overlay blending | Preprocessing, native layers, or renderer extensions as appropriate | No general stock equivalent established |
| Spring/easing animations and simple transitions | GPUI animation and spring APIs | Direct/custom |
| Matched-geometry transitions and animated layout identity | Application-owned geometry interpolation | Custom; not a direct SwiftUI modifier replacement |
| Lottie JSON playback, including user URLs | Native Lottie bridge or independently validated renderer | Native/custom gate |
| Sparkle particles and glowing welcome animation | Custom GPUI drawing or retained Core Animation | Custom/native; blur/glow parity separate |
| SF Symbols and symbol transitions | Native symbol rasterization or explicit asset mapping; custom transitions | Native/custom; not automatic |
| Battery and information popovers | In-window overlays or separate native/GPUI popup windows | Custom/native; window bounds matter |
| Standard settings/onboarding windows | GPUI windows plus macOS configuration | Direct/native |
| Nonactivating notch panels, Spaces, focus transfer | Custom macOS window integration | Native gate |
| Menu-bar status item | AppKit `NSStatusItem`/menu integration | Native; GPUI app menus are not a status item |
| Global shortcut recorder and login toggle | GPUI controls over native registration APIs | Native/custom |
| Accessibility | GPUI AccessKit nodes, roles, actions, text information | Supported infrastructure; per-control work and acceptance required |
| Localization, assets, system accent, stored colors | Explicit resource and native-value adapters | Custom/native; no automatic `.xcstrings`/SwiftUI pipeline |

## 1. App lifecycle and notch windows

Current entry and hosts:

- `anotchup/anotchupApp.swift:24`: preference migration bootstrap, which must remain before preference consumers.
- `anotchup/anotchupApp.swift:40`: SwiftUI `App` and application delegate integration.
- `anotchup/anotchupApp.swift:56`: `MenuBarExtra`.
- `anotchup/anotchupApp.swift:357` and `anotchup/anotchupApp.swift:549`: native windows containing `NSHostingView`.
- `anotchup/components/Settings/SettingsWindowController.swift:62`: settings host.
- `anotchup/components/Notch/AnotchupSkyLightWindow.swift`: the important native panel contract.

The notch panel is transparent, elevated above the main-menu level, present across Spaces and fullscreen applications, and normally non-key. It permits keyboard focus specifically while the goal editor is active. Its key/resign callbacks coordinate focus transfer across displays. It also has screen-recording visibility settings and SkyLight integration.

GPUI has macOS `NSPanel` popup support, transparency, display selection, and multiwindow APIs. Its popup implementation applies `NonactivatingPanel`, joins Spaces, and supports fullscreen auxiliary behavior. This is useful existing support, not a missing windowing system. [G1][G2]

It is not the app's exact panel policy. The public options inspected do not express all of our custom level, editor-dependent key eligibility, SkyLight placement, native close behavior, and recording-visibility rules. Raw native window handles offer an integration point, not a completed adapter. Expect custom platform code or a narrowly maintained backend change if raw-handle configuration is insufficient.

There is also an application-loop constraint. `Application::run_embedded` exists, but its documentation expects an embedding platform whose `run` returns. The audited macOS backend's `run` sets the application delegate and calls `NSApplication.run`. Merely calling `run_embedded` does not establish that stock GPUI can be dropped into our existing AppDelegate/NSPanel host. Choose one owner for the native run loop and delegate, or implement the embedding platform deliberately. [G3]

No public general-purpose `NSViewRepresentable` equivalent was found in the inspected GPUI API. Native NSViews can be integrated through macOS code, but their bounds, stacking, input, accessibility, lifetime, and clipping must be synchronized with GPUI.

**Acceptance:** editor-only keyboard activation, both orders of cross-display focus transfer, Escape/Return, outside clicks, fullscreen Spaces, Mission Control, lock/unlock, screen removal/reconnection, mixed scaling, settings activation, and menu-bar operation. No dead host windows or stale callbacks after teardown.

## 2. Notch shape, clipping, and effects

Relevant code:

- `anotchup/ContentView.swift:198`: clips the content tree with the current notch shape.
- `anotchup/components/Notch/NotchShape.swift`: animated concave top corners and rounded lower corners.
- `anotchup/components/Notch/NotchHomeView.swift:54` and `anotchup/components/Notch/NotchHomeView.swift:80`: blurred album artwork.
- `anotchup/components/Notch/NotchHomeView.swift:460`: animated blur on content collapse.
- `anotchup/components/Notch/AnotchupHeader.swift:27`: header blur.
- `anotchup/animations/HelloAnimation.swift:144`: blurred glow along an animated path.

GPUI can draw the notch outline, rings, progress strokes, rounded rectangles, images, text, shadows, and linear gradients. Paths support curves and arcs. That is sufficient for much of the basic appearance. [G4]

But drawing a shape is not clipping a subtree to that shape. GPUI's documented `ContentMask` is rectangular. Image corner radii do not implement arbitrary clipping of mixed images, text, video, and native views. The surface element even contains a specific TODO for corner radii. A painted black cover is not a general solution where the outside of the notch must remain transparent. [G5]

I did not find a general public equivalent for SwiftUI's per-subtree `.blur`, arbitrary alpha `.mask`, or `.blendMode(.overlay)` in the inspected core rendering primitives. The macOS `Blurred` window background uses `NSVisualEffectView` behind the window. It does not blur the album art or a collapsing subtree. `Window::blur` is focus-related and is not a graphics blur API. [G2][G5]

Possible solutions differ by effect:

- Preblur a changing artwork image and cache the result.
- Animate geometry/opacity directly for simpler transitions.
- Retain a native compositing layer for a specific effect.
- Add an offscreen compositing/filter or masking path to the renderer.
- Deliberately choose a different appearance, if product parity does not require the original effect.

None should be called automatic pixel parity. Avoid silently dropping an effect just because the controls work.

**Acceptance:** transparent notch corners over a nonblack desktop, descendants clipped during expansion, readable text at both display scales, correct blurred artwork, camera clipping, and no black/opaque fringe from the compositing solution.

## 3. Text, editor focus, and accessibility

`anotchup/components/OneGoal/OneGoalViews.swift` includes task text, numeric duration fields, Return submission, cancellation, focus requests, timer actions, labels/hints/values, and a native focus-request view at line 515.

GPUI has focus handles, key/action dispatch, text measurement, and the `EntityInputHandler` interface. The input example implements selected ranges, marked text, UTF-16 translation, replacement, copy, and paste. macOS text shaping uses CoreText. A text editor does not require embedding SwiftUI. Community Input components provide a higher-level implementation. [G6][C1]

That does not prove our editor behaves correctly with CJK composition, dead keys, emoji/grapheme selection, Persian/RTL text, keyboard navigation, and native window focus. In particular, GPUI element focus cannot substitute for the NSPanel's permission to become key. The music UI also uses a Persian-specific font selection that must survive asset/font migration.

Accessibility is present in current GPUI. It uses AccessKit, including a macOS adapter. Its guide requires stable element IDs and appropriate roles; it supports accessible actions and synthetic text children. Custom buttons, sliders, selected tabs, timer values, and text controls still need deliberate semantics. A drawn button without those semantics is not equivalent to our SwiftUI button. [G7]

**Acceptance:** VoiceOver navigation/actions, selected-tab state, task/timer labels and values, editable selection, IME candidate positioning, Return during composition, Escape handling, and focus transfer between display editors. Test Reduce Motion and contrast settings rather than assuming native defaults carry across.

## 4. Camera

`anotchup/components/Webcam/WebcamView.swift:89` embeds an `AVCaptureVideoPreviewLayer`. The current view uses aspect-fill, horizontal mirroring, and rounded/circular clipping.

There are two credible SwiftUI-free routes:

1. Retain AVFoundation and its preview layer in a custom native view bridge.
2. Deliver captured frames to GPUI's Apple `surface` element.

The second route exists in source; it is not hypothetical. However, the audited Metal renderer asserts that the pixel buffer is `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`. An arbitrary BGRA camera buffer cannot be passed through unchanged. The surface corner-radius TODO also matters for this app's circular camera. Buffer format negotiation/conversion, lifetime, aspect-fill, mirroring, clipping, and color behavior all require an explicit design. [G8]

The native preview route avoids replacing the capture pipeline, but does not avoid the native-view composition problem discussed above. Neither route removes permission or capture lifecycle responsibilities.

**Acceptance:** the actual supported camera formats, mirrored aspect-fill, circular and rounded masks, camera unplug/replug, stop during startup, hidden-view shutdown, and no extra continuous copy/render loop when inactive.

## 5. Shelf drag/drop, sharing, and Quick Look

Relevant files:

- `anotchup/components/Shelf/Views/ShelfView.swift`: multitype drops, selection, horizontal content, Quick Look.
- `anotchup/components/Shelf/Views/FileShareView.swift:123`: native anchor for a sharing picker.
- `anotchup/components/Shelf/Views/ShelfItemView.swift:163`: SwiftUI-rendered drag image.
- `anotchup/components/Shelf/Views/ShelfItemView.swift:172`: native drag source, security-scoped URLs, item deletion after successful external movement.
- `anotchup/extensions/NSItemProvider+LoadHelpers.swift`: byte/file/text handling and file-promise ownership.

GPUI provides typed internal drags and macOS external file dragging. The inspected backend creates native dragging items for paths and reads incoming `NSFilenamesPboardType`. Do not describe GPUI as lacking all external drag/drop. [G9]

That path is narrower than our Shelf contract. We also handle web URLs, plain text, data/images, provider-backed files, multiple representations, and security-scoped lifetime. GPUI's file-path event alone does not expose all of those behaviors. Retain or build a native pasteboard/item-provider adapter and preserve copy/move/cancel distinctions.

The current drag-preview renderer is SwiftUI-specific. Replace it with explicit image composition, a suitable offscreen GPUI rendering path if validated, or a native drawing adapter. Normal on-screen rendering is not evidence of a drop-in `ImageRenderer` equivalent.

`NSSharingServicePicker`, native share services, `NSOpenPanel`, and `QLPreviewPanel` do not require SwiftUI. They do require correct native view/window anchors, coordinates, callbacks, and resource retention. Keep those services native rather than pretending GPUI replaces them. Remove the SwiftUI Quick Look modifier and connect the same service lifecycle through a different presenter.

**Acceptance:** Finder multi-file drops, browser URL/text drags, image/data drops, promised files whose source is temporary, security-scoped resources, drag cancellation, successful external moves, sharing cancellation/completion, and Quick Look keyboard dismissal. The host must not delete provider-owned files or release resources before the receiver finishes.

## 6. Music, Calendar, timer, and HUD presentation

These features do not require a special rendering framework:

- Working on's label, countdown, duration editor, and ring can use GPUI text, paths, controls, and state subscriptions.
- Media information, lyrics, artwork, playback controls, and seek/volume sliders can use GPUI elements.
- The visualizer in `anotchup/components/Music/MusicVisualizer.swift` animates four random-height bars with Core Animation. It is not an audio-analysis pipeline. Recreating those bars in GPUI is straightforward in principle.
- Calendar's list, all-day sections, reminder toggles, selection, and scroll-to-event behavior can be rebuilt from list and input primitives.
- `anotchup/components/Calendar/AnotchupCalendar.swift:21` implements a snapping horizontal date wheel. Snap selection, momentum, and haptics are application behavior, not a promised drop-in ScrollView equivalent.
- Inline/open HUDs and battery indicators are labels, icons, bars, and controls connected to native services.

Keep event cadence explicit. Current views include one-second timer updates, quarter-second lyrics updates, tenth-second media-time updates, and repeating visual animations. GPUI does not automatically infer which of these should stop when hidden. Use visibility-aware subscriptions and cancellation; do not turn the whole app into a permanent frame loop.

The feature state packages need not be rewritten merely to change the renderer. A Rust frontend can consume bridged snapshots/commands from Swift components, or their rules can later be ported separately. Existing SwiftUI `Color`, `Image`, `Animation`, and bindings in native facades must not leak into the new frontend API. Carry data, explicit actions, and resource handles instead.

## 7. Animation, Lottie, icons, and assets

GPUI supports duration/easing animation and springs. Its animation extension includes Reduce Motion handling; spring state can preserve position and velocity through an element ID. It is incorrect to assume all animation machinery must be invented. [G10]

The application still owns layout transitions, interrupted-animation semantics, and the equivalents of `matchedGeometryEffect`, `.numericText`, symbol interpolation, and blur replacement. These are not interchangeable just because both frameworks have a spring.

Lottie is a separate dependency:

- `anotchup/components/LottieView.swift:12` wraps a native Lottie animation view.
- `anotchup/components/Music/LottieAnimationView.swift` supplies the current music container.
- `anotchup/components/Settings/SettingsView.swift` allows named custom URLs, speeds, previews, and removal.

No built-in Lottie player was found in the inspected GPUI sources. Animated image support does not parse arbitrary Lottie JSON. Either preserve the native renderer through an adapter or select a renderer and verify its coverage against bundled and user-supplied animations. Replacing a bundled animation with hand-written bars would not preserve the custom-URL feature.

The onboarding sparkle view is a Core Animation particle emitter. It can remain native or become a custom GPUI particle effect. The Hello animation is an animated trimmed path plus glow; its path is easy to express, while the glow depends on the graphics solution.

SF Symbols are widely used, including variants, hierarchical rendering, variable icons, and symbol transitions. GPUI SVG/image support is not an SF Symbols API. Native symbol rasterization or an explicitly mapped asset set can replace static icons. Animation and automatic variant/color behavior need separate treatment. Preserve asset licensing and platform restrictions.

Localizable strings, bundled fonts, images, sound resources, and archived `NSColor` preferences also need explicit resource handling. `anotchup/Localizable.xcstrings` does not become a GPUI localization catalog automatically. Preserve locale-sensitive dates, time formatting, pluralization where used, and accessible names.

## 8. Settings, onboarding, menus, and popovers

All current settings sections can be expressed with GPUI layout and controls: General, Charge, HUD, Media, Calendar, About, Shelf, Appearance, Advanced, and Shortcuts, plus the window/sidebar arrangement. The forms themselves are not a blocker.

The community library documents Input, Select, Slider, ColorPicker, Form, Settings, Tooltip, and Popover controls. These reduce the amount of control work, but are a separately versioned dependency. Its exact GPUI pin must be respected. These are drawn controls, not a guarantee of native AppKit appearance, automatic accessibility, or OS-version styling. [C1][C2]

Keep native backends behind the settings UI:

- Global shortcut registration and conflict handling behind a replacement for `KeyboardShortcuts.Recorder`.
- Login registration behind a replacement for `LaunchAtLogin.Toggle`.
- Permission status, System Settings links, helper authorization, and native dialogs.
- Settings window activation, persistence, size, and Spaces behavior.
- Preference keys, migration order, and opaque stored native values.

Onboarding is ordinary multi-step presentation around camera, calendar, reminders, accessibility, and media permission/actions. Replacing the view does not replace those permissions.

Popover behavior needs care. The macOS backend explicitly rejects `WindowKind::AnchoredPopup` and documents an in-window fallback. That does not mean every GPUI popup is unsupported: the separate generic popup path exists. An in-window popover, however, cannot paint beyond the containing native window. Our battery popover and settings information popovers may need a larger host, a separate popup window, or an AppKit popover to preserve current placement and dismissal. [G11]

`MenuBarExtra` needs an AppKit status-item replacement. GPUI's application menu support does not by itself create the menu-bar status icon. No stock status-item API was found in the inspected core/macOS source.

## 9. Native services that remain outside this decision

These are not SwiftUI responsibilities and do not disappear with GPUI:

- AVFoundation capture and permission handling.
- EventKit events/reminders and access grants.
- AppleScript, MediaRemote, YouTube HTTP/WebSocket integration, artwork and lyrics work.
- Audio playback for timer completion.
- XPC helpers, Accessibility checks, event taps, volume and brightness controls.
- Finder/security-scoped bookmarks, file providers, Quick Look, native sharing.
- Per-display geometry, notch safe areas, Spaces/SkyLight, screen locking, global shortcuts, login registration.
- Application identity, preferences migration, resource bundles, code signing, entitlements, and updater configuration.

GPUI's display API has UUIDs, bounds, visible bounds, and refresh information. That is not proof of an equivalent for every `NSScreen` notch/auxiliary-region measurement. Retain the native geometry adapter where needed.

These adapters can stay Swift/Objective-C or be implemented using Rust's native bindings. Native adapters do not imply retaining SwiftUI. Conversely, removing our SwiftUI view code does not by itself prove that no third-party dependency links SwiftUI internally; check the final dependency graph if zero SwiftUI linkage is a requirement.

## 10. Adoption gates, ordered by decision value

These are proposed acceptance checks, not experiments performed in this audit.

1. **Native notch window:** nonactivating panel, editor-only key eligibility, both focus-transfer orders, fullscreen/Spaces, display changes, lock/unlock, and status-item lifecycle. This decides whether the GPUI macOS backend fits the host contract.
2. **Clipping and compositing:** transparent animated notch silhouette containing text, artwork, and camera. Demonstrate masks, blur/glow, and scaling without replacing transparency with black paint.
3. **Camera and Lottie:** either validated native-view integration or validated GPUI frame pipelines. Include mirroring, masks, user-supplied animation features, teardown, and format failures.
4. **Full Shelf contract:** richer pasteboard representations, promises, drag previews, security scopes, move semantics, sharing, and Quick Look. File-only drag success is insufficient.
5. **Text and accessibility:** IME, emoji, RTL, keyboard-only use, VoiceOver roles/actions, timer announcements, Reduce Motion, and popup focus/dismissal.
6. **Lifecycle and power:** updates stop when hidden; idle, active animation, video, and multi-display behavior are measured independently. Framework choice is not performance evidence.
7. **Distribution:** supported macOS versions and architectures, bundling fonts/assets/helpers, signing/notarization, entitlements, and third-party licenses. The existing macOS 14 target versus MediaRemoteAdapter built for macOS 15 remains a separate issue, not a GPUI fix.

If the first four gates pass, I would regard a full SwiftUI frontend replacement as a sound direction for this app. If they require a permanent platform/rendering fork, that is a real property of the chosen stack, even when rewrite cost is excluded. Decide knowingly whether that ownership is acceptable.

## 11. Source index

Pinned links make the capability claims reproducible.

- [G1: GPUI window options and kinds](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/platform.rs#L2602).
- [G2: macOS window construction and native background implementation](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui_macos/src/window.rs#L1010).
- [G3: embedded application entry](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/app.rs#L331), [macOS run loop](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui_macos/src/platform.rs#L527), and [raw window handle](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/window.rs#L7866).
- [G4: path construction](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/path_builder.rs), [background types](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/color.rs#L745).
- [G5: content masks](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/window.rs#L2458), [surface painting](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/elements/surface.rs#L100), [style implementation](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/style.rs).
- [G6: editable input example](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/examples/input.rs), [CoreText implementation](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui_apple/src/text_system.rs).
- [G7: GPUI accessibility guide](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/_accessibility.rs), [macOS accessibility adapter](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui_macos/src/window.rs#L2415).
- [G8: pixel-buffer surface](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/elements/surface.rs), [Metal pixel-format assertion](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui_apple/src/metal_renderer.rs#L1411).
- [G9: external drag creation](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui_macos/src/window.rs#L2273), [incoming path extraction](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui_macos/src/window.rs#L3755).
- [G10: animation and spring APIs](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui/src/elements/animation.rs).
- [G11: macOS anchored-popup rejection](https://github.com/zed-industries/zed/blob/4a6121bb0f10c6e8037b741b7dc0a4cd639ae289/crates/gpui_macos/src/platform.rs#L747).
- [C1: community controls](https://github.com/longbridge/gpui-kit/tree/b2aaa3e5f9a387dea74981586bfca33e7e08420d/website/base/primitives).
- [C2: community version and GPUI pins](https://github.com/longbridge/gpui-kit/blob/b2aaa3e5f9a387dea74981586bfca33e7e08420d/Cargo.toml#L61).

## Appendix: complete SwiftUI-related file inventory

This inventory is an accounting of source dependencies, not a claim that every file defines an active screen. "No active caller found" is a static reference-search result, not a runtime coverage result. Native files without SwiftUI imports, such as the notch panels and platform service implementations, are covered in the sections above.

| File | Replacement or retained responsibility |
| --- | --- |
| `anotchup/AnotchupViewCoordinator.swift` | Shared navigation/preview state; replace UI values and subscriptions, retain lifecycle contracts. |
| `anotchup/ContentView.swift` | Main GPUI tree; custom notch clipping, gestures, effects, state subscriptions. |
| `anotchup/MediaControllers/AppleMusicController.swift` | Native media adapter, not a rendered screen; remove incidental UI coupling. |
| `anotchup/MediaControllers/SpotifyController.swift` | Native media adapter, not a rendered screen. |
| `anotchup/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift` | HTTP/WebSocket media adapter, not a rendered screen. |
| `anotchup/Shortcuts/ShortcutConstants.swift` | Native shortcut definitions; preserve registration and stored bindings. |
| `anotchup/animations/HelloAnimation.swift` | Paths and timed stroke drawing; custom glow/blur solution. |
| `anotchup/animations/drop.swift` | Animation values referenced by models; replace SwiftUI animation types. |
| `anotchup/anotchupApp.swift` | Application ownership, menu-bar item, three hosting paths, composition and migration. |
| `anotchup/components/AnimatedFace.swift` | Paths/rectangles and blinking animation; own and stop the repeating task. |
| `anotchup/components/BottomRoundedRectangle.swift` | Custom GPUI path or per-corner geometry. |
| `anotchup/components/Calendar/AnotchupCalendar.swift` | Date wheel, event lists, reminder controls, locale formatting and haptics. |
| `anotchup/components/EmptyState.swift` | Text/face/transition; no active caller found outside its preview. |
| `anotchup/components/HoverButton.swift` | GPUI button/hover state; symbol animation replacement. |
| `anotchup/components/Live activities/AnotchupBattery.swift` | Battery graphics and native-size popover behavior. |
| `anotchup/components/Live activities/DownloadView.swift` | Placeholder download UI; no active caller found for `DownloadArea`. |
| `anotchup/components/Live activities/InlineHUD.swift` | Icons, labels, sliders, and native volume/brightness callbacks. |
| `anotchup/components/Live activities/LiveActivityModifier.swift` | Generic overlay layout; no active application use found. |
| `anotchup/components/Live activities/MarqueeTextView.swift` | Measured text and clipped scrolling animation. |
| `anotchup/components/Live activities/OpenNotchHUD.swift` | Capsule layout, icons, slider, percentages. |
| `anotchup/components/Live activities/SystemEventIndicatorModifier.swift` | HUD state and draggable progress graphics; native service callbacks. |
| `anotchup/components/LottieView.swift` | Native Lottie view bridge or separately validated Lottie renderer. |
| `anotchup/components/Music/LottieAnimationView.swift` | Lottie container and scaling; depends on the renderer choice. |
| `anotchup/components/Music/MusicVisualizer.swift` | Four animated bars; replace the CALayer wrapper with GPUI drawing if desired. |
| `anotchup/components/Notch/AnotchupExtrasMenu.swift` | Buttons and links; no active caller found outside its preview. |
| `anotchup/components/Notch/AnotchupHeader.swift` | Tabs, task/battery/camera controls, geometry and collapse effects. |
| `anotchup/components/Notch/NotchHomeView.swift` | Media, camera, Calendar composition; several blur and matched-geometry effects. |
| `anotchup/components/Notch/NotchShape.swift` | Shape drawing is supported; subtree clipping needs a separate solution. |
| `anotchup/components/Onboarding/MusicControllerSelectionView.swift` | Selection controls over existing media setup. |
| `anotchup/components/Onboarding/OnboardingFinishView.swift` | Completion presentation and actions. |
| `anotchup/components/Onboarding/OnboardingView.swift` | Multi-step flow around native permissions. |
| `anotchup/components/Onboarding/PermissionsRequestView.swift` | Permission-status presentation and explicit native requests. |
| `anotchup/components/Onboarding/SparkleView.swift` | Native CAEmitterLayer bridge or custom particles. |
| `anotchup/components/Onboarding/WelcomeView.swift` | Text/buttons, native visual material, particles, blending and blur. |
| `anotchup/components/OneGoal/OneGoalViews.swift` | Editable text, duration controls, ring, accessibility, and editor-only native focus. |
| `anotchup/components/ProgressIndicator.swift` | Arc/text progress; no active caller found outside its preview. |
| `anotchup/components/Settings/EditPanelView.swift` | Panel itself appears preview-only; `VisualEffectView` is active in onboarding. |
| `anotchup/components/Settings/ListItemPopover.swift` | Information-button popover; preserve out-of-window placement as needed. |
| `anotchup/components/Settings/MusicSlotConfigurationView.swift` | Internal reorder palette, drop slots, and remove target. |
| `anotchup/components/Settings/SettingsView.swift` | Full settings forms and sheets; shortcut/login/color/Lottie adapters remain. |
| `anotchup/components/Settings/SettingsWindowController.swift` | Replace hosting view and preserve native activation/window behavior. |
| `anotchup/components/Settings/SoftwareUpdater.swift` | Update menu/control integration; updater remains disabled as configured. |
| `anotchup/components/Shelf/Services/QuickLookService.swift` | Retain native Quick Look service; replace SwiftUI presenter modifier. |
| `anotchup/components/Shelf/ViewModels/ShelfItemViewModel.swift` | Selection/thumbnail/action state; map native images and updates explicitly. |
| `anotchup/components/Shelf/Views/DragPreviewView.swift` | Offscreen drag-image composition must replace SwiftUI rendering. |
| `anotchup/components/Shelf/Views/FileShareView.swift` | Multitype drop UI and native share-picker anchor. |
| `anotchup/components/Shelf/Views/ShelfItemView.swift` | Item display plus custom native drag source and security-scope ownership. |
| `anotchup/components/Shelf/Views/ShelfView.swift` | List/selection/drop/Quick Look orchestration. |
| `anotchup/components/Tabs/TabButton.swift` | Buttons, tooltips, selected accessibility state. |
| `anotchup/components/Tabs/TabSelectionView.swift` | Shared selection with animated indicator geometry. |
| `anotchup/components/TestView.swift` | Preview-only fluid-slider Canvas/filter example; not a required released feature. |
| `anotchup/components/Tips/TipStore.swift` | Donation/tips UI; caller in settings is commented out, preview remains. |
| `anotchup/components/Webcam/WebcamView.swift` | Native video preview, mirroring/masks, permission UI. |
| `anotchup/components/WhatsNewView.swift` | Preview-only information dialog based on references found. |
| `anotchup/extensions/ActionBar.swift` | Layout helper; express through GPUI elements. |
| `anotchup/extensions/BundleInfos.swift` | Bundle metadata, not a rendering requirement. |
| `anotchup/extensions/Button+Bouncing.swift` | Press-state animation and button background. |
| `anotchup/extensions/Color+AccentColor.swift` | Native/system accent conversion and stored color compatibility. |
| `anotchup/extensions/ConditionalModifier.swift` | SwiftUI composition helper; no runtime capability to preserve. |
| `anotchup/extensions/KeyboardShortcutsHelper.swift` | Shortcut behavior/native registration integration. |
| `anotchup/extensions/MouseTracker.swift` | Native pointer/display lookup, not a GPUI view. |
| `anotchup/extensions/NSImage+Extensions.swift` | Image conversion/processing; bridge images without SwiftUI `Image`. |
| `anotchup/extensions/PanGesture.swift` | Local native scroll monitor, momentum/end policy, and view drag gesture. |
| `anotchup/helpers/AppIcons.swift` | Native image assets; convert or keep image lookup native. |
| `anotchup/managers/CalendarManager.swift` | Calendar state/native facade, not a rendering requirement. |
| `anotchup/managers/MusicManager.swift` | Media state, image/color and animation values; separate frontend types. |
| `anotchup/managers/WebcamManager.swift` | Capture session/preview-layer facade; retain or adapt without SwiftUI. |
| `anotchup/models/AnotchupViewModel.swift` | Shell presentation state and effect wiring; replace UI values, preserve contracts. |
| `anotchup/models/BatteryStatusViewModel.swift` | Battery presentation state/native colors/icons. |
| `anotchup/models/Constants.swift` | Preferences/defaults and native presentation values; preserve persisted meanings. |
| `anotchup/sizing/matters.swift` | Screen/notch measurements and sizes; keep native measurement boundary. |
| `anotchup/utils/Logger.swift` | Logging utility with UI import; not a rendering capability. |
