import AppKit
import QuartzCore

// Exercises the actual AppKit spectrum layers and loads sounds without playback.
@main
struct OneGoalRendererTests {
    @MainActor private static var checks = 0

    @MainActor
    static func main() {
        expect(NSApplication.shared.activationPolicy() == .prohibited, "renderer test cannot activate")
        let spectrum = AudioSpectrum(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        spectrum.setPlaying(false)
        for size in [NSSize(width: 10, height: 10), NSSize(width: 16, height: 12),
                     NSSize(width: 14, height: 10), NSSize(width: 20, height: 20)] {
            spectrum.setFrameSize(size)
            spectrum.layout()
            let bars = spectrum.layer?.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
            expect(bars.count == 4, "spectrum retains four bars at \(size)")
            let first = bars.first!, last = bars.last!
            expect(near(first.frame.minX, size.width - last.frame.maxX), "left and right padding match at \(size)")
            expect(near(first.position.x + last.position.x, size.width), "spectrum is horizontally centered at \(size)")
            for bar in bars {
                expect(near(bar.position.y, size.height / 2), "bar stays vertically centered at \(size)")
                expect(bar.bounds.height <= size.height, "bar layers shrink to the actual mask height")
                expect(bar.frame.minX >= -0.001 && bar.frame.maxX <= size.width + 0.001, "bar fits mask width")
                expect(near(bar.transform.m22, 0.35), "paused music leaves stationary short bars")
            }
            if size.width == 10 {
                let radius: CGFloat = 9.5 // Inner edge of the fixed 20pt, 1pt ring.
                let cornerDistance = hypot(size.width / 2, size.height / 2)
                expect(cornerDistance < radius, "compact visualizer has clearance inside ring")
            }
        }
        spectrum.setFrameSize(.zero)
        spectrum.layout()
        expect(spectrum.layer?.sublayers?.count == 4, "zero-sized transition is harmless")

        for size: CGFloat in [5, 7, 16, 24] {
            let font = NSFont.systemFont(ofSize: size)
            let lineHeight = font.ascender - font.descender + font.leading
            for padding: CGFloat in [0, 1, 6, 12] {
                let height = OneGoalLayout.captionHeight(lineHeight: lineHeight, padding: padding)
                expect(height >= lineHeight + 2 * padding + 1, "real font metrics fit automatic caption height")
            }
        }
        for choice in OneGoalCompletionSound.allCases where choice != .silent {
            let url = URL(fileURLWithPath: "/System/Library/Sounds/\(choice.rawValue).aiff")
            let sound = NSSound(contentsOf: url, byReference: false)
            expect(sound != nil, "\(choice.rawValue) is available without bundled dependencies")
            expect((sound?.duration ?? 0) > 0, "\(choice.rawValue) is a valid sound file")
        }
        expect(!NSApp.isActive && NSApp.windows.isEmpty, "renderer test never activates or creates windows")
        print("One Goal renderer: \(checks) checks passed (no audio played)")
    }

    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }
}
