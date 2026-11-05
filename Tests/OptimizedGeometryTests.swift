// A separate optimized AppKit consumer is essential: package-only tests with
// Foundation imports do not reproduce the Swift 6.4.2 SIL deserialization crash.
import AppKit
import NotchShell

let screen = CGRect(x: -1200, y: -700, width: 1200, height: 800)
let size = CGSize(width: 200, height: 80)
let origin = NotchGeometry.origin(screen: screen, window: size)
precondition(origin == CGPoint(x: -700, y: 20))
precondition(NotchGeometry.contains(origin, screen: screen, notch: size))
precondition(!NotchGeometry.contains(CGPoint(x: -701, y: 20), screen: screen, notch: size))
precondition(NotchGeometry.closedHeight(height: 32, hide: true, hasCutout: false) == 0)
precondition(NotchGeometry.closedHeight(height: 32, hide: true, hasCutout: true) == 32)
precondition(NotchGeometry.chinHeight(menuBar: 40, closed: 32, hiddenTitleBar: true, isOpen: false) == 8)
precondition(NotchGeometry.chinHeight(menuBar: 40, closed: 32, hiddenTitleBar: true, isOpen: true) == 0)
print("Optimized cross-module geometry checks passed")
