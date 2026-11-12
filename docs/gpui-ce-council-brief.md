# GPUI-CE rewrite council brief

## Decision

Choose the smallest executable technical-gate prototype for an anotchup Rust and GPUI-CE rewrite. Verify CE itself rather than assuming the earlier Zed GPUI audit applies.

## Baseline and scope

- Branch: `rewrite/gpui-ce`, based on `193ead6f1ae9015213f9fca86a3f6e101bc1f7f2` at the user's explicit request.
- Retain the existing Swift implementation as a behavioral reference and preserve its tests and notices.
- Drop Shelf and Lottie from the rewrite. Node extensions are out of scope for now.
- Start with native notch-window/focus behavior, transparent clipping, and camera composition.
- Do not replace the installed app, change user preferences, request permissions, or run camera/window experiments during the council.
- A successful build or source audit is not native runtime acceptance or performance evidence.

## Evidence

Read `docs/gpui-feasibility-audit.md` as historical evidence about upstream GPUI, not CE. Inspect current canonical CE sources at https://github.com/gpui-ce/gpui-ce and pin every consequential finding to a revision or published version. Inspect local native panel, editor focus, camera, and shell contracts.

## Roster and protocol

Two independent T3 delegates, using the parent's Pi model and inherited settings, provide read-only advice. The installed roster had no council profiles. The skill's oracle/reviewer fallback is adapted to T3 at the user's request: both delegates receive fresh explicit context rather than native profile/fork inheritance. They must not edit files, read peer reports, or spawn children. This is a declared transport/profile deviation, not a claim that native oracle/reviewer profiles were instantiated.

Use the council skill's structured pass-1 report, under about 600 words. The parent then forms a claim matrix. At most one cross-examination pass follows, using new T3 tasks with curated claims and explicit prior evidence. No pass for polish alone. The parent records accepted/rejected advice, unresolved owner decisions, evidence, run IDs, confidence, and the implementation choice.

The initial task based on `origin/main` was canceled after the user clarified the branch ancestry. It is not evidence for the corrected decision.
