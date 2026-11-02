import Combine
import Foundation

@MainActor
final class OneGoalStore: ObservableObject {
    static let shared = OneGoalStore()
    static let storageKey = "oneGoal.current"

    @Published private(set) var goal: OneGoal
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           var saved = try? JSONDecoder().decode(OneGoal.self, from: data) {
            saved.text = OneGoal.normalized(saved.text)
            if saved.text.isEmpty {
                saved = OneGoal()
                defaults.removeObject(forKey: Self.storageKey)
            } else if let countdown = saved.countdown,
                      !countdown.duration.isFinite || countdown.duration <= 0 || countdown.duration > 86_400 || !countdown.deadline.timeIntervalSince1970.isFinite {
                saved.countdown = nil
            }
            goal = saved
        } else {
            goal = OneGoal()
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    func save(text: String) {
        var updated = goal
        updated.text = OneGoal.normalized(text)
        if updated.text.isEmpty {
            updated = OneGoal()
        }
        update(updated)
    }

    func startCountdown(minutes: Int, now: Date = Date()) {
        guard !goal.text.isEmpty, (1...1440).contains(minutes) else { return }
        var updated = goal
        let duration = TimeInterval(minutes * 60)
        updated.countdown = OneGoal.Countdown(duration: duration, deadline: now.addingTimeInterval(duration))
        update(updated)
    }

    func clearCountdown() {
        var updated = goal
        updated.countdown = nil
        update(updated)
    }

    func complete() {
        update(OneGoal())
    }

    private func update(_ updated: OneGoal) {
        guard updated != goal else { return }
        if updated.text.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else if let data = try? JSONEncoder().encode(updated) {
            defaults.set(data, forKey: Self.storageKey)
        }
        goal = updated
    }
}
