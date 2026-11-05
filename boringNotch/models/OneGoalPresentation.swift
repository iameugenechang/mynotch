import Foundation

enum OneGoalCompletionSound: String, CaseIterable {
    case silent = "Silent"
    case glass = "Glass"
    case tink = "Tink"
    case pop = "Pop"
    case ping = "Ping"

    var label: String {
        switch self {
        case .silent: return "Silent"
        case .glass: return "Glass (soft chime)"
        case .tink: return "Tink (light bell)"
        case .pop: return "Pop (soft click)"
        case .ping: return "Ping (bright bell)"
        }
    }
}

/// Shared, deterministic layout rules for collapsed, preview, and expanded states.
struct OneGoalLayout {
    let menuBarHeight: CGFloat
    let captionHeight: CGFloat
    let hitPadding: CGFloat
    let verticalOffset: CGFloat

    static func captionHeight(lineHeight: CGFloat, padding: CGFloat) -> CGFloat {
        lineHeight.rounded(.up) + 2 * padding + 1
    }

    static func timerWidth(notchWidth: CGFloat, curveInset: CGFloat) -> CGFloat {
        max(0, notchWidth - 2 * curveInset)
    }

    var collapsedOrigin: CGFloat {
        max(0, menuBarHeight - captionHeight - hitPadding + verticalOffset)
    }

    var bottomInset: CGFloat {
        max(0, menuBarHeight - collapsedOrigin - hitPadding - captionHeight)
    }

    func extensionHeight(contentHeight: CGFloat, isPreview: Bool) -> CGFloat {
        let normal = max(0, collapsedOrigin + hitPadding + captionHeight - contentHeight)
        return isPreview ? max(normal, captionHeight + bottomInset) : normal
    }

    func captionOrigin(bodyHeight: CGFloat) -> CGFloat {
        max(0, bodyHeight - captionHeight - hitPadding - bottomInset)
    }
}
