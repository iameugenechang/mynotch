//! Decides when a window with no frame demand may stop its display link.
//!
//! GPUI wakes the platform whenever a window becomes dirty or has next-frame
//! callbacks. Without that demand, every vsync tick is a main-thread wakeup
//! that draws nothing.
use std::time::{Duration, Instant};

/// Keep ticking this long after the last demand. GPUI sustains presentation
/// for a second after high-rate input, and a frame drawn outside a frame
/// request is presented on the next tick.
pub(crate) const GRACE: Duration = Duration::from_millis(1500);

pub(crate) struct FrameIdle {
    last_demand: Instant,
}

impl FrameIdle {
    pub(crate) fn new(now: Instant) -> Self {
        Self { last_demand: now }
    }

    /// Record demand that arrived outside a tick, such as a restarted link.
    pub(crate) fn note_demand(&mut self, now: Instant) {
        self.last_demand = now;
    }

    /// Call once per tick, after the frame callback. Returns whether the
    /// display link should stop.
    pub(crate) fn tick(&mut self, demand: bool, now: Instant) -> bool {
        if demand {
            self.last_demand = now;
            return false;
        }
        now.saturating_duration_since(self.last_demand) >= GRACE
    }
}
