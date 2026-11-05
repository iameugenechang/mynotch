import Foundation

// App-owned presentation and media policy, separate from Working on logic.
@main
struct OneGoalPresentationTests {
    private static var checks = 0

    static func main() {
        layoutRules()
        pausedMediaVisibility()
        print("Working on presentation/media: \(checks) checks passed")
    }

    private static func layoutRules() {
        expect(OneGoalLayout.captionHeight(lineHeight: 8.4, padding: 1) == 12, "caption height fits font and padding")
        for lineHeight: CGFloat in [8.4, 14.2, 29.1] {
            for padding: CGFloat in [0, 1, 6, 12] {
                expect(OneGoalLayout.captionHeight(lineHeight: lineHeight, padding: padding) >= lineHeight + 2 * padding,
                       "automatic height cannot clip the requested font/padding")
            }
        }
        let normal = OneGoalLayout(menuBarHeight: 33, captionHeight: 12, hitPadding: 6, verticalOffset: 12)
        expect(normal.extensionHeight(contentHeight: 33, isPreview: false) == 12, "collapsed extension is one caption high")
        expect(normal.captionOrigin(bodyHeight: 45) == 27, "collapsed caption is at bottom")
        expect(normal.extensionHeight(contentHeight: 190, isPreview: false) == 0, "expanded goal does not add height")
        expect(normal.captionOrigin(bodyHeight: 190) == 172, "expanded caption is at bottom, not header")
        expect(normal.extensionHeight(contentHeight: 60, isPreview: true) == 12, "preview reserves a separate footer")
        expect(normal.captionOrigin(bodyHeight: 72) + 6 == 60, "preview footer does not cover preview content")
        let timerWidth = OneGoalLayout.timerWidth(notchWidth: 267, curveInset: 20)
        expect(timerWidth == 227, "timer uses collapsed inner width")
        expect(OneGoalLayout.timerWidth(notchWidth: 20, curveInset: 20) == 0, "timer width cannot be negative")
        for offset: CGFloat in [-24, -10, 0, 12, 64] {
            for height: CGFloat in [8, 12, 20, 48] {
                let layout = OneGoalLayout(menuBarHeight: 33, captionHeight: height, hitPadding: 6, verticalOffset: offset)
                for content: CGFloat in [33, 60, 190] {
                    for preview in [false, true] {
                        let body = content + layout.extensionHeight(contentHeight: content, isPreview: preview)
                        let origin = layout.captionOrigin(bodyHeight: body)
                        expect(origin >= 0 && origin + 6 + height <= body + 0.001, "caption stays inside unified silhouette")
                        if preview {
                            expect(origin + 6 >= content - 0.001, "preview content is never covered")
                        }
                    }
                }
            }
        }
        expect(OneGoalCompletionSound.allCases.count == 5, "four sounds plus Silent")
    }

    private static func pausedMediaVisibility() {
        let now = Date()
        expect(MediaVisibilityPolicy.hasCurrentTrack(title: "A track", lastUpdated: now), "real track is available")
        expect(!MediaVisibilityPolicy.hasCurrentTrack(title: " \n", lastUpdated: now), "empty metadata cannot pin media")
        expect(!MediaVisibilityPolicy.hasCurrentTrack(title: "Unknown", lastUpdated: now), "fallback title cannot pin media")
        expect(!MediaVisibilityPolicy.hasCurrentTrack(title: "I'm Handsome", lastUpdated: .distantPast), "startup placeholder cannot pin media")
        for keep in [false, true] {
            for hasTrack in [false, true] {
                expect(MediaVisibilityPolicy.shouldShowPlayer(isPlaying: true, isIdle: true, keepWhilePaused: keep, hasTrack: hasTrack), "playing media is visible")
                expect(MediaVisibilityPolicy.shouldShowPlayer(isPlaying: false, isIdle: false, keepWhilePaused: keep, hasTrack: hasTrack), "pause grace period stays visible")
                expect(MediaVisibilityPolicy.shouldShowPlayer(isPlaying: false, isIdle: true, keepWhilePaused: keep, hasTrack: hasTrack) == (keep && hasTrack), "paused media obeys the option and track availability")
            }
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }
}
