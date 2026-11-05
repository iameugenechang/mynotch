# System HUD contract

`SystemHUD` owns wire validation, authorization-to-activation policy, and connection generations. App composition supplies authorization and event-tap effects. Native XPC calls, Core Graphics event taps, brightness I/O, and sound remain adapters.

- `HUDMessage` accepts only the four supported kinds and finite values in 0...1 in the existing string-valued JSON format. Malformed input does not become a brightness event or zero value.
- `HUDActivation` never prompts at startup or on an authorization notification. Explicit preference enablement may prompt. Disable, replacement, and terminal stop reject late authorization results before acquiring a tap. Revocation releases the tap.
- `ConnectionOwner` reuses a live connection. Loss drops only that generation, closes its resources, and allows the next request to reconnect. An old invalidation callback cannot erase a newer connection. Results from replaced connections or canceled tasks are rejected. Native clients retain their existing optional/Boolean fallback API; those fallbacks do not distinguish every transport failure for UI consumers.
- The XPC client and event-tap owner are main-actor confined. Authorization polling uses weak ownership, cancellation, and a monitor generation; stopping a monitor prevents its late result from publishing. App termination stops monitoring and invalidates the connection.
- Core Graphics callbacks run on the main run loop where their source is installed. Acquiring an event tap never occurs in package tests.

Five tests cover decoding, authorization cancellation/revocation, connection reuse/reconnection, late callbacks/results, and failed construction. These test the production owners with controlled effects, not an actual signed helper or event tap. Signed XPC and macOS permission acceptance still require an opt-in manual run.
