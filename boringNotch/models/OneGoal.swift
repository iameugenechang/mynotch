import Foundation

/// Only the current definition of done and its optional countdown. No history.
struct OneGoal: Codable, Equatable {
    var text: String = ""
    var countdown: Countdown?

    struct Countdown: Codable, Equatable {
        let duration: TimeInterval
        let deadline: Date

        func remaining(at date: Date) -> TimeInterval {
            max(0, min(duration, deadline.timeIntervalSince(date)))
        }

        func fractionRemaining(at date: Date) -> Double {
            guard duration > 0 else { return 0 }
            return remaining(at: date) / duration
        }

        func remainingText(at date: Date) -> String {
            let seconds = Int(remaining(at: date).rounded(.up))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }

    static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
