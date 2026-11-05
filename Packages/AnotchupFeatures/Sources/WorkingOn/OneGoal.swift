import Foundation

/// What you're currently working on and its optional countdown. No history.
/// Keep the legacy type name and Codable schema compatible with saved snapshots.
public struct OneGoal: Codable, Equatable {
    public var text: String
    public var countdown: Countdown?

    public init(text: String = "", countdown: Countdown? = nil) {
        self.text = text
        self.countdown = countdown
    }

    public struct Countdown: Codable, Equatable {
        public static func parseDuration(minutes: String, seconds: String) -> Int? {
            let minutes = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
            let seconds = seconds.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mins = Int(minutes.isEmpty ? "0" : minutes),
                  let secs = Int(seconds.isEmpty ? "0" : seconds),
                  (0...1440).contains(mins), (0...59).contains(secs) else { return nil }
            let total = mins * 60 + secs
            return (1...86_400).contains(total) ? total : nil
        }

        public let duration: TimeInterval
        public var deadline: Date
        // Optional fields keep snapshots from earlier versions readable.
        public var pausedRemaining: TimeInterval?
        public var completionHandled: Bool?

        public init(duration: TimeInterval, deadline: Date,
                    pausedRemaining: TimeInterval? = nil, completionHandled: Bool? = nil) {
            self.duration = duration
            self.deadline = deadline
            self.pausedRemaining = pausedRemaining
            self.completionHandled = completionHandled
        }

        public var isPaused: Bool { pausedRemaining != nil }
        public var isFinished: Bool { completionHandled == true }

        public func remaining(at date: Date) -> TimeInterval {
            guard !isFinished else { return 0 }
            return max(0, min(duration, pausedRemaining ?? deadline.timeIntervalSince(date)))
        }

        public func fractionRemaining(at date: Date) -> Double {
            guard duration > 0 else { return 0 }
            return remaining(at: date) / duration
        }

        public func remainingText(at date: Date) -> String {
            let seconds = Int(remaining(at: date).rounded(.up))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }

        public func statusText(at date: Date) -> String {
            if isFinished || remaining(at: date) <= 0 { return "Finished" }
            let time = remainingText(at: date)
            return isPaused ? "\(time) paused" : "\(time) remaining"
        }
    }

    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
