import Combine
import Foundation
import WorkingOn

@MainActor
public final class UserDefaultsOneGoalPersistence: OneGoalPersistence {
    // Compatibility with all existing Working on snapshots.
    public static let storageKey = "oneGoal.current"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> Data? { defaults.data(forKey: Self.storageKey) }
    public func save(_ data: Data) { defaults.set(data, forKey: Self.storageKey) }
    public func clear() { defaults.removeObject(forKey: Self.storageKey) }
}

@MainActor
public struct RunLoopCountdownScheduler: CountdownScheduling {
    public init() {}

    public func schedule(every interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        precondition(interval > 0 && interval.isFinite)
        let timer = Timer(timeInterval: interval, repeats: true) { timer in
            Task { @MainActor in
                // A tick may already be queued when its registration is cancelled.
                guard timer.isValid else { return }
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return AnyCancellable { timer.invalidate() }
    }
}

public extension OneGoalStore {
    // Compatibility constructor while callers move to explicit composition.
    static var storageKey: String { UserDefaultsOneGoalPersistence.storageKey }

    convenience init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = { Date() }) {
        self.init(persistence: UserDefaultsOneGoalPersistence(defaults: defaults),
                  scheduler: RunLoopCountdownScheduler(), clock: clock)
    }
}
