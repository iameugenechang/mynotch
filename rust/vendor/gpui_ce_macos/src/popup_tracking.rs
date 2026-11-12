// Extracted from GPUI-CE window.rs at 81742184cb1df090709257a5e4061eba44fa8e8a.
// Licensed under Apache-2.0; see ../LICENSE-APACHE and ../PATCH.md.
use objc2::{class, msg_send, rc::Retained, runtime::AnyObject};
use objc2_foundation::{NSPoint, NSRect, NSSize, NSUInteger};

pub(crate) const OPTIONS: NSUInteger = 0x01 | 0x02 | 0x80 | 0x200;

/// Construct the popup tracking area without constructing a window.
///
/// SAFETY: Called on the main thread with a valid owner that outlives the area.
pub(crate) unsafe fn new(owner: *mut AnyObject) -> Retained<AnyObject> {
    unsafe {
        let allocated: *mut AnyObject = msg_send![class!(NSTrackingArea), alloc];
        // An initializer returns an object, not void, and may replace `allocated`.
        let initialized: *mut AnyObject = msg_send![
            allocated,
            initWithRect: NSRect::new(NSPoint::new(0., 0.), NSSize::new(0., 0.)),
            options: OPTIONS,
            owner: owner,
            userInfo: std::ptr::null_mut::<AnyObject>()
        ];
        Retained::from_raw(initialized).expect("NSTrackingArea initialization failed")
    }
}
