import Foundation

/// Only the current definition of done and its optional countdown. No history.
struct OneGoal: Codable, Equatable {
    var text: String = ""
    var countdown: Countdown?

    struct Countdown: Codable, Equatable {
        static func parseDuration(minutes: String, seconds: String) -> Int? {
            let minutes = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
            let seconds = seconds.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mins = Int(minutes.isEmpty ? "0" : minutes),
                  let secs = Int(seconds.isEmpty ? "0" : seconds),
                  (0...1440).contains(mins), (0...59).contains(secs) else { return nil }
            let total = mins * 60 + secs
            return (1...86_400).contains(total) ? total : nil
        }

        let duration: TimeInterval
        var deadline: Date
        // Optional fields keep snapshots from earlier versions readable.
        var pausedRemaining: TimeInterval? = nil
        var completionHandled: Bool? = nil

        var isPaused: Bool { pausedRemaining != nil }
        var isFinished: Bool { completionHandled == true }

        func remaining(at date: Date) -> TimeInterval {
            guard !isFinished else { return 0 }
            return max(0, min(duration, pausedRemaining ?? deadline.timeIntervalSince(date)))
        }

        func fractionRemaining(at date: Date) -> Double {
            guard duration > 0 else { return 0 }
            return remaining(at: date) / duration
        }

        func remainingText(at date: Date) -> String {
            let seconds = Int(remaining(at: date).rounded(.up))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }

        func statusText(at date: Date) -> String {
            if isFinished || remaining(at: date) <= 0 { return "Finished" }
            let time = remainingText(at: date)
            return isPaused ? "\(time) paused" : "\(time) remaining"
        }
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

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
