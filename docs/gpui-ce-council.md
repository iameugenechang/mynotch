# GPUI-CE council decision

## Decision and scope

Start a separate macOS Rust executable on `rewrite/gpui-ce`, based on `193ead6`. Pin GPUI-CE to `81742184cb1df090709257a5e4061eba44fa8e8a`. Preserve the Swift implementation and tests as a reference. Shelf and Lottie are excluded from the rewrite.

The first executable is a composition-and-panel experiment, not a replacement application. GPUI owns NSApplication and the event loop. A small Objective-C adapter configures hidden popup panels, native masks, and synthetic CoreVideo buffers. No installed app changes, preferences, permissions, or real camera acquisition are part of this slice. Starting the graphical experiment is explicit, not part of automated verification.

## Accepted advice

- Pin the source and lock dependencies. Both advisors independently selected the same CE revision. Its manifest says 0.2.2; a search result for the published 0.3.0 is not the same source.
- Test overflowing child content inside the actual concave notch mask. Painting the silhouette is not clipping.
- Exercise CE's actual Surface path with synthetic full-range bi-planar 420 buffers. Never construct a capture session in synthetic mode.
- Include CE content/backdrop blur fixtures. The earlier upstream audit's blur limitations do not describe this CE revision.
- Keep the native panel's GPUI delegate and state ownership intact. Guard every borrowed native-handle use by window lifetime.
- Prototype a per-instance subclass for key eligibility, installed only while hidden on the main thread. Validate the exact expected GPUI class and equal instance size. Missing associated state denies key status; never allow main-window status. Ending editing explicitly resigns key status. Do not swizzle methods on GPUI's shared classes.
- Retain a single-crate, source-pinned `gpui_ce_macos` patch as the fallback if the instance-subclass experiment fails. Never patch the global Cargo cache.

The platform advisor initially preferred a backend patch. After inspecting inherited state access, `isKindOfClass` checks and explicit NSPanel deallocation, pass 2 accepted a guarded per-instance subclass for the experiment. This is source-based permission to test the approach, not proof of native safety.

## Rejected claims and unresolved requirements

`focus: false` is not editor-only key eligibility. `run_embedded` is not a way to retain an unchanged Swift application delegate. A raw handle does not prove correct teardown. A successful build does not prove Metal shader initialization, compositor alpha, focus, Spaces, or performance.

An outer notch mask does not establish the camera's separate circular/rounded crop. Keep that gate open. Full text input/IME, real capture permissions and shutdown, display events, lock-screen/private SkyLight behavior, Intel support, and production backdrop effects remain acceptance work. Public collection flags must not be described as SkyLight parity. The owner need not decide these release requirements to build the experiment; no requirement is silently declared passed.

## Evidence

All CE paths below refer to `81742184cb1df090709257a5e4061eba44fa8e8a` in https://github.com/gpui-ce/gpui-ce:

- `crates/gpui_macos/src/window.rs`: class construction at 578-600; popup style at 1181-1183; delegate at 1305-1310; popup flags at 1366-1392; raw handle at 2476-2485; state/deallocation at 2513-2576.
- `crates/gpui_macos/src/platform.rs:511-540`: application ownership.
- `crates/gpui/src/window.rs:2166-2205`: rectangular content masks.
- `crates/gpui/src/elements/surface.rs:108-184`: fit policy and missing corner masks.
- `crates/gpui_apple/src/metal_renderer.rs:1889-1892`: required pixel format.
- `crates/gpui/examples/learn/blur.rs:1-17`: content and backdrop blur.

Local behavior comes from `anotchup/components/Notch/AnotchupSkyLightWindow.swift`, `anotchup/components/Notch/NotchShape.swift`, `anotchup/components/OneGoal/OneGoalViews.swift`, and `anotchup/components/Webcam/WebcamView.swift` at `193ead6`. The parent downloaded the canonical pinned archive to `/tmp/anotchup-gpui-ce-source`; pass 2 explicitly noted that this archive has no Git metadata. Implementation verification subsequently checked Cargo's resolved metadata: one canonical CE family at the exact revision, including one macOS backend. The actual executable built and headless contracts passed; no graphical acceptance was performed.

## Implementation follow-up: popup initializer

The owner's first live run failed before the per-instance adapter executed: upstream popup creation declared an object-returning `NSTrackingArea` initializer as void. The parent used the single-crate packaging approach above for this separate backend bug, not because subclassing had been disproved. `rust/vendor/gpui_ce_macos/PATCH.md` records the change and the failing-then-passing headless regression. No additional council pass was launched. The original visual/focus acceptance limits remain.

## Roster and pass record

Two independent T3 fresh-context advisors used `pi / openai-codex/gpt-6-astra`, inherited high thinking. No native council profiles were available. The oracle/reviewer fallback was adapted to explicit T3 briefs as requested; native profile settings and oracle fork context were not inherited. Advisors were read-only, with no peer-report access or children.

- Platform pass 1 task suffix: `59114b5c-0d31-49ae-a9e7-9d877785853d`, run ordinal 1.
- Rendering/camera pass 1 task suffix: `8c0538fd-5efb-4b0e-a3a9-603c4b0f1df2`, run ordinal 1.
- Platform pass 2 task suffix: `9c4db43f-5bf6-47c3-85ac-b7dc1aa121c8`, run ordinal 1. Fresh context with its prior findings and three curated claims, not a resumed native advisor.
- Initial wrong-base task `d3b917ce-537c-40ed-8408-f1c7cb1fcf6a` was canceled and excluded.

Pass 1: two reports, four shared decisions (pin, app ownership, synthetic-first, runtime gates), one design choice requiring cross-examination. Pass 2 refined that choice; no recommendation-changing evidence dispute remained. Stopped at the two-pass cap. Confidence is medium. Native failures or a supported CE per-window key policy would change the design.
