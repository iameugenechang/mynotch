import Combine
import Foundation

@MainActor
public final class OneGoalStore: ObservableObject {
    @Published public private(set) var goal: OneGoal
    public var onCountdownFinished: (() -> Void)?
    private let persistence: any OneGoalPersistence
    private let scheduler: any CountdownScheduling
    private let clock: () -> Date
    private var completionMonitor: AnyCancellable?
    private var monitorGeneration = UUID()
    private var monitoringEnabled = false

    public init(persistence: any OneGoalPersistence, scheduler: any CountdownScheduling,
         clock: @escaping () -> Date) {
        self.persistence = persistence
        self.scheduler = scheduler
        self.clock = clock
        if let data = persistence.load(),
           var saved = try? JSONDecoder().decode(OneGoal.self, from: data) {
            saved.text = OneGoal.normalized(saved.text)
            if saved.text.isEmpty {
                saved = OneGoal()
                persistence.clear()
            } else if let countdown = saved.countdown,
                      !countdown.duration.isFinite || countdown.duration <= 0 || countdown.duration > 86_400 || !countdown.deadline.timeIntervalSince1970.isFinite
                        || countdown.pausedRemaining.map({ !$0.isFinite || $0 <= 0 || $0 > countdown.duration }) == true {
                saved.countdown = nil
            }
            goal = saved
        } else {
            goal = OneGoal()
            persistence.clear()
        }
    }

    public func save(text: String) {
        var updated = goal
        updated.text = OneGoal.normalized(text)
        if updated.text.isEmpty {
            updated = OneGoal()
        }
        update(updated)
    }

    public func startCountdown(minutes: Int, now: Date? = nil) {
        guard (1...1440).contains(minutes) else { return }
        startCountdown(seconds: minutes * 60, now: now)
    }

    public func startCountdown(seconds: Int, now: Date? = nil) {
        guard !goal.text.isEmpty, (1...86_400).contains(seconds) else { return }
        let now = now ?? clock()
        var updated = goal
        let duration = TimeInterval(seconds)
        updated.countdown = OneGoal.Countdown(duration: duration, deadline: now.addingTimeInterval(duration))
        update(updated)
    }

    public func pauseCountdown(now: Date? = nil) {
        guard var countdown = goal.countdown, !countdown.isPaused, !countdown.isFinished else { return }
        let remaining = countdown.remaining(at: now ?? clock())
        guard remaining > 0 else {
            finishCountdown()
            return
        }
        countdown.pausedRemaining = remaining
        var updated = goal
        updated.countdown = countdown
        update(updated)
    }

    public func resumeCountdown(now: Date? = nil) {
        guard var countdown = goal.countdown, let remaining = countdown.pausedRemaining, remaining > 0 else { return }
        countdown.deadline = (now ?? clock()).addingTimeInterval(remaining)
        countdown.pausedRemaining = nil
        var updated = goal
        updated.countdown = countdown
        update(updated)
    }

    public func restartCountdown(now: Date? = nil) {
        guard let countdown = goal.countdown, !goal.text.isEmpty else { return }
        var updated = goal
        updated.countdown = OneGoal.Countdown(duration: countdown.duration, deadline: (now ?? clock()).addingTimeInterval(countdown.duration))
        update(updated)
    }

    /// One app-level monitor, independent of how many notch views are visible.
    public func startMonitoringCountdown() {
        guard !monitoringEnabled else { return }
        monitoringEnabled = true
        // Do not chime on launch for a timer that expired while the app was off.
        if var countdown = goal.countdown, !countdown.isPaused, !countdown.isFinished,
           countdown.remaining(at: clock()) <= 0 {
            countdown.completionHandled = true
            var updated = goal
            updated.countdown = countdown
            update(updated)
        } else {
            scheduleCompletionMonitor()
        }
    }

    public func stopMonitoringCountdown() {
        monitoringEnabled = false
        cancelCompletionMonitor()
    }

    private func cancelCompletionMonitor() {
        monitorGeneration = UUID()
        completionMonitor?.cancel()
        completionMonitor = nil
    }

    private func scheduleCompletionMonitor() {
        cancelCompletionMonitor()
        guard monitoringEnabled, let countdown = goal.countdown,
              !countdown.isPaused, !countdown.isFinished else { return }
        if countdown.remaining(at: clock()) <= 0 {
            finishCountdown()
            return
        }
        let generation = monitorGeneration
        completionMonitor = scheduler.schedule(every: 1) { [weak self] in
            guard let self, self.monitorGeneration == generation else { return }
            self.refreshCountdown()
        }
    }

    public func refreshCountdown() {
        guard monitoringEnabled, let countdown = goal.countdown,
              !countdown.isPaused, !countdown.isFinished else { return }
        if countdown.remaining(at: clock()) <= 0 { finishCountdown() }
    }

    private func finishCountdown() {
        guard var countdown = goal.countdown, !countdown.isFinished else { return }
        countdown.pausedRemaining = nil
        countdown.completionHandled = true
        var updated = goal
        updated.countdown = countdown
        // Persist the handled flag before playing, including across relaunches.
        update(updated)
        onCountdownFinished?()
    }

    public func clearCountdown() {
        var updated = goal
        updated.countdown = nil
        update(updated)
    }

    public func complete() {
        update(OneGoal())
    }

    private func update(_ updated: OneGoal) {
        guard updated != goal else { return }
        if updated.text.isEmpty {
            persistence.clear()
        } else if let data = try? JSONEncoder().encode(updated) {
            persistence.save(data)
        }
        goal = updated
        scheduleCompletionMonitor()
    }
}
