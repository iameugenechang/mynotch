//! Untitled popups must start borderless, before AppKit creates title-bar KVO.
use objc2_app_kit::NSWindowStyleMask;

pub(crate) fn for_popup(has_titlebar: bool, requested: NSWindowStyleMask) -> NSWindowStyleMask {
    if has_titlebar {
        requested | NSWindowStyleMask::NonactivatingPanel
    } else {
        NSWindowStyleMask::Borderless | NSWindowStyleMask::NonactivatingPanel
    }
}
