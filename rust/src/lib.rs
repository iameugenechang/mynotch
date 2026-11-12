//! Pure contracts for the gate, not a claim of native window acceptance.
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Lifetime {
    display: u64,
    generation: u64,
}
#[derive(Default)]
pub struct DisplayLifetimes {
    generation: u64,
    displays: BTreeMap<u64, (Lifetime, bool)>,
    focused: Option<Lifetime>,
}
impl DisplayLifetimes {
    pub fn register(&mut self, display: u64) -> Lifetime {
        if let Some((old, _)) = self.displays.remove(&display)
            && self.focused == Some(old)
        {
            self.focused = None;
        }
        self.generation = self
            .generation
            .checked_add(1)
            .expect("lifetime counter exhausted");
        let token = Lifetime {
            display,
            generation: self.generation,
        };
        self.displays.insert(display, (token, false));
        token
    }
    pub fn is_current(&self, token: Lifetime) -> bool {
        self.displays
            .get(&token.display)
            .is_some_and(|(current, _)| *current == token)
    }
    pub fn begin_editing(&mut self, token: Lifetime) -> bool {
        if !self.is_current(token) {
            return false;
        }
        self.displays.get_mut(&token.display).unwrap().1 = true;
        true
    }
    pub fn can_become_key(&self, token: Lifetime) -> bool {
        self.is_current(token) && self.displays[&token.display].1
    }
    pub fn became_key(&mut self, token: Lifetime) -> bool {
        if !self.can_become_key(token) {
            return false;
        }
        self.focused = Some(token);
        true
    }
    pub fn resigned_key(&mut self, token: Lifetime) {
        if !self.is_current(token) {
            return;
        }
        self.displays.get_mut(&token.display).unwrap().1 = false;
        if self.focused == Some(token) {
            self.focused = None;
        }
    }
    pub fn remove(&mut self, token: Lifetime) {
        if !self.is_current(token) {
            return;
        }
        self.resigned_key(token);
        self.displays.remove(&token.display);
    }
    pub fn focused(&self) -> Option<Lifetime> {
        self.focused
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Segment {
    Move(Point),
    Line(Point),
    Quad { control: Point, end: Point },
    Close,
}
/// Port of anotchup/components/Notch/NotchShape.swift, originally by Kai Azim
/// (DynamicNotchKit), modified by Alexander. Original attribution/licenses retained.
/// Coordinates are top-left, with concave shoulders and convex lower corners.
pub fn notch_path(width: f64, height: f64, top: f64, bottom: f64) -> Option<Vec<Segment>> {
    if ![width, height, top, bottom].iter().all(|x| x.is_finite())
        || width <= 0.0
        || height <= 0.0
        || top < 0.0
        || bottom < 0.0
        || top + bottom > height
        || 2.0 * (top + bottom) > width
    {
        return None;
    }
    let p = |x, y| Point { x, y };
    Some(vec![
        Segment::Move(p(0.0, 0.0)),
        Segment::Quad {
            control: p(top, 0.0),
            end: p(top, top),
        },
        Segment::Line(p(top, height - bottom)),
        Segment::Quad {
            control: p(top, height),
            end: p(top + bottom, height),
        },
        Segment::Line(p(width - top - bottom, height)),
        Segment::Quad {
            control: p(width - top, height),
            end: p(width - top, height - bottom),
        },
        Segment::Line(p(width - top, top)),
        Segment::Quad {
            control: p(width - top, 0.0),
            end: p(width, 0.0),
        },
        Segment::Close,
    ])
}

/// Packed format shared with the native CoreGraphics mask builder.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct PathCommand {
    pub kind: u32,
    pub control: Point,
    pub end: Point,
}
pub fn path_commands(path: &[Segment]) -> Vec<PathCommand> {
    let zero = Point { x: 0.0, y: 0.0 };
    path.iter()
        .map(|s| match *s {
            Segment::Move(p) => PathCommand {
                kind: 0,
                control: zero,
                end: p,
            },
            Segment::Line(p) => PathCommand {
                kind: 1,
                control: zero,
                end: p,
            },
            Segment::Quad { control, end } => PathCommand {
                kind: 2,
                control,
                end,
            },
            Segment::Close => PathCommand {
                kind: 3,
                control: zero,
                end: zero,
            },
        })
        .collect()
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Crop {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}
pub fn aspect_fill(source: (f64, f64), target: (f64, f64)) -> Option<Crop> {
    let (sw, sh) = source;
    let (tw, th) = target;
    if ![sw, sh, tw, th].iter().all(|x| x.is_finite() && *x > 0.0) {
        return None;
    }
    let scale = (tw / sw).max(th / sh);
    Some(Crop {
        x: (tw - sw * scale) / 2.0,
        y: (th - sh * scale) / 2.0,
        width: sw * scale,
        height: sh * scale,
    })
}
/// Horizontal mapping used before upload, since CE Surface has no mirror control.
pub fn source_x(x: usize, width: usize, mirrored: bool) -> Option<usize> {
    if x >= width {
        None
    } else {
        Some(if mirrored { width - 1 - x } else { x })
    }
}

/// Synthetic NV12: asymmetric luminance, chroma quadrants and a moving bar.
/// Allocated only on explicit frame changes; no camera or background producer.
pub struct Nv12Frame {
    pub width: usize,
    pub height: usize,
    pub y: Vec<u8>,
    pub uv: Vec<u8>,
}
impl Nv12Frame {
    pub fn new(width: usize, height: usize, phase: usize, mirrored: bool) -> Option<Self> {
        if width == 0
            || height == 0
            || !width.is_multiple_of(2)
            || !height.is_multiple_of(2)
            || width > 4096
            || height > 4096
        {
            return None;
        }
        let mut y = vec![0; width * height];
        let mut uv = vec![0; width * height / 2];
        for row in 0..height {
            for col in 0..width {
                let x = source_x(col, width, mirrored)?;
                y[row * width + col] = if x.abs_diff(phase % width) < 8 {
                    235
                } else if x < width / 2 {
                    70
                } else {
                    180
                };
            }
        }
        for row in 0..height / 2 {
            for pair in 0..width / 2 {
                let x = source_x(pair, width / 2, mirrored)?;
                let offset = row * width + pair * 2;
                uv[offset] = if x < width / 4 { 90 } else { 170 };
                uv[offset + 1] = if row < height / 4 { 90 } else { 180 };
            }
        }
        Some(Self {
            width,
            height,
            y,
            uv,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn initial_panel_is_not_key_eligible() {
        let mut d = DisplayLifetimes::default();
        let a = d.register(1);
        assert!(!d.can_become_key(a));
        assert!(!d.became_key(a));
        assert!(d.begin_editing(a));
        assert!(d.became_key(a));
        d.resigned_key(a);
        assert!(!d.can_become_key(a));
        assert_eq!(d.focused(), None);
    }
    #[test]
    fn transfer_works_in_both_callback_orders() {
        for resign_first in [true, false] {
            let mut d = DisplayLifetimes::default();
            let a = d.register(1);
            let b = d.register(2);
            d.begin_editing(a);
            d.became_key(a);
            d.begin_editing(b);
            if resign_first {
                d.resigned_key(a);
                d.became_key(b);
            } else {
                d.became_key(b);
                d.resigned_key(a);
            }
            assert_eq!(d.focused(), Some(b));
            assert!(!d.can_become_key(a));
        }
    }
    #[test]
    fn stale_removal_or_focus_cannot_touch_recreated_display() {
        let mut d = DisplayLifetimes::default();
        let old = d.register(1);
        d.begin_editing(old);
        let new = d.register(1);
        d.begin_editing(new);
        d.became_key(new);
        d.remove(old);
        d.resigned_key(old);
        assert!(!d.begin_editing(old));
        assert!(!d.became_key(old));
        assert_eq!(d.focused(), Some(new));
        d.remove(new);
        assert!(!d.is_current(new));
    }
    #[test]
    fn displays_have_independent_protection() {
        let mut d = DisplayLifetimes::default();
        let a = d.register(1);
        let b = d.register(2);
        d.begin_editing(a);
        assert!(!d.can_become_key(b));
        d.remove(b);
        assert!(d.can_become_key(a));
    }
    #[test]
    fn notch_matches_source_control_points() {
        let path = notch_path(400.0, 200.0, 6.0, 14.0).unwrap();
        assert_eq!(path.len(), 9);
        assert_eq!(
            path[1],
            Segment::Quad {
                control: Point { x: 6.0, y: 0.0 },
                end: Point { x: 6.0, y: 6.0 }
            }
        );
        assert_eq!(
            path[3],
            Segment::Quad {
                control: Point { x: 6.0, y: 200.0 },
                end: Point { x: 20.0, y: 200.0 }
            }
        );
        assert_eq!(
            path[7],
            Segment::Quad {
                control: Point { x: 394.0, y: 0.0 },
                end: Point { x: 400.0, y: 0.0 }
            }
        );
        assert_eq!(path_commands(&path).last().unwrap().kind, 3);
    }
    #[test]
    fn invalid_geometry_fails_closed() {
        for v in [f64::NAN, f64::INFINITY, 0.0, -1.0] {
            assert!(notch_path(v, 200.0, 6.0, 14.0).is_none());
        }
        assert!(notch_path(20.0, 200.0, 6.0, 14.0).is_none());
        assert!(notch_path(400.0, 10.0, 6.0, 14.0).is_none());
    }
    #[test]
    fn nv12_planes_mirror_pixels_and_chroma_pairs_not_bytes() {
        let a = Nv12Frame::new(32, 16, 0, false).unwrap();
        let b = Nv12Frame::new(32, 16, 0, true).unwrap();
        assert_eq!(a.y.len(), 512);
        assert_eq!(a.uv.len(), 256);
        for row in 0..16 {
            for x in 0..32 {
                assert_eq!(a.y[row * 32 + x], b.y[row * 32 + 31 - x]);
            }
        }
        for row in 0..8 {
            for pair in 0..16 {
                assert_eq!(
                    &a.uv[row * 32 + pair * 2..row * 32 + pair * 2 + 2],
                    &b.uv[row * 32 + (15 - pair) * 2..row * 32 + (15 - pair) * 2 + 2]
                );
            }
        }
        assert_ne!(a.y, Nv12Frame::new(32, 16, 16, false).unwrap().y);
        assert!(Nv12Frame::new(3, 2, 0, false).is_none());
        assert!(Nv12Frame::new(0, 2, 0, false).is_none());
    }
    #[test]
    fn crop_and_mirror_are_explicit() {
        let crop = aspect_fill((640.0, 480.0), (200.0, 200.0)).unwrap();
        assert!((crop.x + 100.0 / 3.0).abs() < 1e-9);
        assert!((crop.width - 800.0 / 3.0).abs() < 1e-9);
        assert_eq!(crop.height, 200.0);
        assert!(aspect_fill((0.0, 1.0), (1.0, 1.0)).is_none());
        assert_eq!(source_x(0, 640, true), Some(639));
        assert_eq!(source_x(639, 640, true), Some(0));
        assert_eq!(source_x(4, 640, false), Some(4));
        assert_eq!(source_x(640, 640, true), None);
    }
}
