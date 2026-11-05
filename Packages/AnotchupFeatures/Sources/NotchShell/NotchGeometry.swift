// Import the module that owns these geometry types explicitly. A Foundation-only
// import crashes Swift 6.4.2's SIL linker in optimized AppKit clients.
// See docs/release-compiler-crash.md and scripts/test-optimized-geometry.sh.
import CoreGraphics

public enum NotchGeometry {
    public static func origin(screen: CGRect, window: CGSize) -> CGPoint {
        CGPoint(x: screen.origin.x + (screen.size.width - window.width) / 2,
                y: screen.origin.y + screen.size.height - window.height)
    }
    public static func contains(_ point: CGPoint, screen: CGRect, notch: CGSize) -> Bool {
        let middle = screen.origin.x + screen.size.width / 2
        return point.y >= screen.origin.y + screen.size.height - notch.height
            && point.x >= middle - notch.width / 2 && point.x <= middle + notch.width / 2
    }
    public static func closedHeight(height: Double, hide: Bool, hasCutout: Bool) -> Double {
        hide && !hasCutout ? 0 : height
    }
    public static func chinHeight(menuBar: Double, closed: Double, hiddenTitleBar: Bool, isOpen: Bool) -> Double {
        hiddenTitleBar && !isOpen && closed > 0 ? max(0, menuBar - closed) : 0
    }
}
