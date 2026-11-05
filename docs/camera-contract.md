# Camera contract

`CameraFeature` owns the app-wide capture request, authorization-request lifetime, and start/stop reconciliation. `CameraDevice` supplies passive availability/authorization checks and explicit async request, start, and stop operations. `WebcamManager` maps the component to native preview properties; app composition constructs its AVFoundation adapter.

Start never requests permission. Denied access or missing devices cannot acquire capture. Repeated start/stop commands are idempotent. Stop or shutdown during acquisition waits for completion, then releases the late resource. A start during stop is processed after release. Failed acquisition invokes cleanup before allowing a retry. Shutdown is terminal. Concurrent authorization requests share one task, and granting access alone does not start capture.

AVFoundation configuration, start, stop, and cleanup run on one serial queue. The preview layer is created on the main actor. Device disconnect stops the request; reconnect only refreshes availability. The existing app-wide toggle semantics are preserved, not replaced with per-window leases. The UI uses actual authorization-request state instead of a two-second timer.

Six component tests cover denied/unavailable state, idempotence, stop/shutdown during acquisition, setup failure, retry, and authorization coalescing. The native adapter compiles in the unsigned app build but is not exercised with real camera devices. Native adapter conformance and physical preview acceptance remain open. No camera, permission dialog, or application was launched during verification.
