//! Borrow native handles only during a live GPUI callback. Never store them.
use anotchup_gates::{Nv12Frame, PathCommand, notch_path, path_commands};
use core_foundation::base::TCFType;
use core_video::pixel_buffer::{CVPixelBuffer, CVPixelBufferRef};
use gpui::Window;
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use std::ffi::c_void;
// Compile the exact production initializer, not a test copy of the message send.
#[path = "../vendor/gpui_ce_macos/src/frame_idle.rs"]
mod frame_idle;
#[path = "../vendor/gpui_ce_macos/src/popup_style.rs"]
mod popup_style;
#[path = "../vendor/gpui_ce_macos/src/popup_tracking.rs"]
mod popup_tracking;
unsafe extern "C" {
    fn gate_install(view: *mut c_void) -> bool;
    fn gate_mask(view: *mut c_void, commands: *const PathCommand, count: usize) -> bool;
    fn gate_show(view: *mut c_void);
    fn gate_edit(view: *mut c_void, editing: bool) -> bool;
    fn gate_is_editing(view: *mut c_void) -> bool;
    fn gate_resize(view: *mut c_void, width: f64, height: f64);
    fn gate_frame(width: usize, height: usize, y: *const u8, uv: *const u8) -> CVPixelBufferRef;
    fn gate_native_contracts() -> bool;
    fn gate_path_contains(
        commands: *const PathCommand,
        count: usize,
        height: f64,
        x: f64,
        y: f64,
    ) -> bool;
}
fn with_view<T>(window: &Window, action: impl FnOnce(*mut c_void) -> T) -> T {
    let handle = HasWindowHandle::window_handle(window).expect("live native window handle");
    let RawWindowHandle::AppKit(handle) = handle.as_raw() else {
        panic!("macOS gate only")
    };
    action(handle.ns_view.as_ptr())
}
pub fn install(window: &Window) -> bool {
    // SAFETY: GPUI supplies a live NSView on its main thread; no pointer escapes.
    with_view(window, |view| unsafe { gate_install(view) })
}
pub fn mask(window: &Window) -> bool {
    let size = window.viewport_size();
    let Some(path) = notch_path(
        f32::from(size.width) as f64,
        f32::from(size.height) as f64,
        6.0,
        14.0,
    ) else {
        return false;
    };
    let commands = path_commands(&path);
    // SAFETY: command layout matches gate.h and its slice remains live throughout the call.
    with_view(window, |view| unsafe {
        gate_mask(view, commands.as_ptr(), commands.len())
    })
}
pub fn show(window: &Window) {
    with_view(window, |view| unsafe { gate_show(view) });
}
pub fn edit(window: &Window, editing: bool) -> bool {
    with_view(window, |view| unsafe { gate_edit(view, editing) })
}
pub fn is_editing(window: &Window) -> bool {
    with_view(window, |view| unsafe { gate_is_editing(view) })
}
pub fn resize(window: &Window, width: f64, height: f64) {
    with_view(window, |view| unsafe { gate_resize(view, width, height) });
}
pub fn frame(phase: usize, mirrored: bool) -> CVPixelBuffer {
    let planes = Nv12Frame::new(320, 240, phase, mirrored).expect("valid synthetic dimensions");
    // SAFETY: C copies both bounded planes synchronously and returns a +1 CF object.
    let raw = unsafe {
        gate_frame(
            planes.width,
            planes.height,
            planes.y.as_ptr(),
            planes.uv.as_ptr(),
        )
    };
    assert!(!raw.is_null(), "CoreVideo allocation failed");
    unsafe { CVPixelBuffer::wrap_under_create_rule(raw) }
}
fn tracking_area_contract() {
    use objc2::{
        MainThreadMarker, msg_send,
        rc::{Retained, autoreleasepool},
        runtime::AnyObject,
    };
    use objc2_foundation::{NSObject, NSRect, NSUInteger};
    let _main = MainThreadMarker::new().expect("tracking area contract requires main thread");
    autoreleasepool(|_| {
        let owner = NSObject::new();
        // SAFETY: NSObject remains alive until after the tracking area is dropped.
        unsafe {
            let owner_ptr = Retained::as_ptr(&owner) as *mut AnyObject;
            let area = popup_tracking::new(owner_ptr);
            let actual_owner: *mut AnyObject = msg_send![&*area, owner];
            let options: NSUInteger = msg_send![&*area, options];
            let rect: NSRect = msg_send![&*area, rect];
            assert_eq!(actual_owner, owner_ptr);
            assert_eq!(options, popup_tracking::OPTIONS);
            assert_eq!(rect.size.width, 0.0);
            assert_eq!(rect.size.height, 0.0);
        }
    });
}
fn blocks_contract() {
    use block::ConcreteBlock;
    use std::{cell::Cell, rc::Rc};
    struct Capture(Rc<Cell<usize>>);
    impl Drop for Capture {
        fn drop(&mut self) {
            self.0.set(self.0.get() + 1);
        }
    }
    let drops = Rc::new(Cell::new(0));
    let capture = Capture(drops.clone());
    let stack = ConcreteBlock::new(move |value: i32| {
        let _keep_capture = &capture;
        value + 7
    });
    // SAFETY: Exact i32 -> i32 signature, single-threaded, live block/capture.
    assert_eq!(unsafe { stack.call((5,)) }, 12);
    // These exercise the real system _Block_copy/_Block_release and class ISA.
    let heap = stack.copy();
    let retained = heap.clone();
    drop(heap);
    assert_eq!(drops.get(), 0);
    assert_eq!(unsafe { retained.call((8,)) }, 15);
    drop(retained);
    assert_eq!(drops.get(), 1, "captured resources must be released once");
}
fn popup_style_contract() {
    use objc2_app_kit::NSWindowStyleMask as Style;
    // The old backend supplied Titled|FullSizeContentView even for titlebar:None.
    let old_untitled = Style::Titled | Style::FullSizeContentView;
    assert_eq!(
        popup_style::for_popup(false, old_untitled),
        Style::Borderless | Style::NonactivatingPanel,
    );
    // Explicit title bars retain their requested controls and resize policy.
    let titled = Style::Titled | Style::Closable | Style::Resizable;
    assert_eq!(
        popup_style::for_popup(true, titled),
        titled | Style::NonactivatingPanel,
    );
}
fn frame_idle_contract() {
    use frame_idle::{FrameIdle, GRACE};
    use std::time::{Duration, Instant};
    let start = Instant::now();
    let short = GRACE - Duration::from_millis(1);
    let mut idle = FrameIdle::new(start);
    // A fresh window keeps ticking through the grace period, then parks.
    assert!(!idle.tick(false, start + short));
    assert!(idle.tick(false, start + GRACE));
    // Demand keeps the link alive and restarts the grace period.
    assert!(!idle.tick(true, start + GRACE * 3));
    assert!(!idle.tick(false, start + GRACE * 3 + short));
    assert!(idle.tick(false, start + GRACE * 4));
    // A restarted link gets a full grace period, and a clock that appears to
    // run backwards never parks early.
    idle.note_demand(start + GRACE * 10);
    assert!(!idle.tick(false, start + GRACE * 10 + short));
    assert!(!idle.tick(false, start));
}
pub fn contracts() -> bool {
    frame_idle_contract();
    popup_style_contract();
    blocks_contract();
    tracking_area_contract();
    assert_eq!(std::mem::size_of::<PathCommand>(), 40);
    let commands = path_commands(&notch_path(300.0, 200.0, 6.0, 14.0).unwrap());
    let contains =
        |x, y| unsafe { gate_path_contains(commands.as_ptr(), commands.len(), 200.0, x, y) };
    // Tests the actual Rust silhouette through the native coordinate conversion.
    (unsafe { gate_native_contracts() })
        && contains(150.0, 100.0)
        && contains(20.0, 190.0)
        && !contains(3.0, 5.0)
        && !contains(6.0, 199.0)
        && !contains(297.0, 5.0)
        && !contains(294.0, 199.0)
}
