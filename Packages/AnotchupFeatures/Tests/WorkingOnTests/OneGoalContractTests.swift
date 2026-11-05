import Combine
import Foundation
import XCTest
import WorkingOn
import WorkingOnAdapters

@MainActor
final class MemoryGoalPersistence: OneGoalPersistence {
    private var data: Data?
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
    func clear() { data = nil }
}

@MainActor
final class ManualCountdownScheduler: CountdownScheduling {
    final class Registration {
        let action: @MainActor @Sendable () -> Void
        var active = true
        init(_ action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    }
    private(set) var registrations: [Registration] = []
    var activeCount: Int { registrations.filter(\.active).count }

    func schedule(every interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        precondition(interval > 0 && interval.isFinite)
        let registration = Registration(action)
        registrations.append(registration)
        return AnyCancellable { registration.active = false }
    }

    func tick() {
        for registration in registrations where registration.active { registration.action() }
    }

    // Deliberately violate cancellation to simulate a previously queued callback.
    func deliverStale(_ index: Int) { registrations[index].action() }
}

final class OneGoalContractTests: XCTestCase {
    func testContracts() async {
        await Self.runChecks()
    }

    @MainActor private static var checks = 0

    @MainActor
    private static func runChecks() async {
        checks = 0
        persistenceContract(MemoryGoalPersistence())
        let suite = "anotchup.contracts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("untouched", forKey: "oneGoalFontSize")
        persistenceContract(UserDefaultsOneGoalPersistence(defaults: defaults))
        expect(defaults.string(forKey: "oneGoalFontSize") == "untouched", "adapter only changes its snapshot key")
        let bytes = Data("legacy snapshot".utf8)
        defaults.set(bytes, forKey: "oneGoal.current")
        expect(UserDefaultsOneGoalPersistence(defaults: defaults).load() == bytes, "adapter reads the literal legacy key")
        let adapter = UserDefaultsOneGoalPersistence(defaults: defaults)
        adapter.save(Data([1, 2, 3]))
        expect(UserDefaultsOneGoalPersistence(defaults: defaults).load() == Data([1, 2, 3]), "new adapter reads the same stored bytes")

        let manual = ManualCountdownScheduler()
        await schedulerContract(manual, advance: { manual.tick() })
        await schedulerContract(RunLoopCountdownScheduler(), advance: {
            // Yield the main actor so scheduled callbacks can run. No app or input events.
            try? await Task.sleep(nanoseconds: 200_000_000)
        })
        componentContract(MemoryGoalPersistence())
        adapter.clear()
        componentContract(adapter)
        print("Working on contracts: \(checks) assertions executed")
    }

    @MainActor
    private static func persistenceContract(_ persistence: any OneGoalPersistence) {
        expect(persistence.load() == nil, "storage starts absent")
        for bytes in [Data(), Data([0, 255, 128]), Data("not JSON".utf8)] {
            persistence.save(bytes)
            expect(persistence.load() == bytes, "storage preserves opaque bytes without validation")
        }
        persistence.clear()
        persistence.clear()
        expect(persistence.load() == nil, "clear is idempotent")
    }

    @MainActor
    private static func schedulerContract(_ scheduler: any CountdownScheduling, advance: @MainActor () async -> Void) async {
        var calls = 0
        var token: AnyCancellable? = scheduler.schedule(every: 0.02) { calls += 1 }
        expect(calls == 0, "registration never invokes its callback inline")
        await advance()
        expect(calls > 0, "retained registration delivers a tick")
        let first = calls
        await advance()
        expect(calls > first, "registration repeats")
        token?.cancel()
        token?.cancel()
        let cancelled = calls
        await advance()
        expect(calls == cancelled, "explicit cancellation stops delivery and is idempotent")
        token = scheduler.schedule(every: 0.02) { calls += 1 }
        await advance()
        expect(calls > cancelled, "a new registration works after cancellation")
        token = nil
        let released = calls
        await advance()
        expect(calls == released, "releasing the token cancels delivery")
    }

    @MainActor
    private static func componentContract(_ persistence: any OneGoalPersistence) {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduler = ManualCountdownScheduler()
        var store: OneGoalStore? = OneGoalStore(persistence: persistence, scheduler: scheduler, clock: { now })
        expect(scheduler.activeCount == 0, "constructing a component starts no timer")
        var firstDisplay = OneGoal()
        var secondDisplay = OneGoal()
        let first = store!.$goal.sink { firstDisplay = $0 }
        let second = store!.$goal.sink { secondDisplay = $0 }
        var completions = 0
        store!.onCountdownFinished = {
            let saved = try! JSONDecoder().decode(OneGoal.self, from: persistence.load()!)
            expect(saved.countdown?.isFinished == true, "persist handled state before emitting completion")
            completions += 1
        }
        store!.startMonitoringCountdown()
        store!.save(text: "One shared goal")
        store!.startCountdown(seconds: 10)
        expect(scheduler.activeCount == 1, "two consumers share one monitor")
        let oldRegistration = scheduler.registrations.count - 1
        store!.startMonitoringCountdown()
        expect(scheduler.registrations.count == 1, "duplicate startup does not register again")
        expect(firstDisplay == secondDisplay && firstDisplay == store!.goal, "consumers observe the same state")
        now.addTimeInterval(1)
        store!.restartCountdown()
        expect(scheduler.activeCount == 1, "replacement cancels the previous registration")
        now.addTimeInterval(11)
        scheduler.deliverStale(oldRegistration)
        expect(completions == 0 && store!.goal.countdown?.isFinished == false, "stale callback cannot finish a replacement, even when it is due")
        scheduler.tick()
        scheduler.tick()
        expect(completions == 1 && scheduler.activeCount == 0, "current tick finishes once and releases monitoring")
        expect(firstDisplay.countdown?.isFinished == true && secondDisplay == firstDisplay, "completion reaches both consumers")

        store!.restartCountdown()
        let beforePause = scheduler.registrations.count - 1
        now.addTimeInterval(2)
        store!.pauseCountdown()
        expect(scheduler.activeCount == 0, "pause cancels monitoring")
        now.addTimeInterval(100)
        scheduler.deliverStale(beforePause)
        expect(store!.goal.countdown?.pausedRemaining == 8 && completions == 1, "late tick cannot change paused state")
        store!.resumeCountdown()
        expect(scheduler.activeCount == 1, "resume registers once")
        let beforeStop = scheduler.registrations.count - 1
        store!.stopMonitoringCountdown()
        store!.stopMonitoringCountdown()
        expect(scheduler.activeCount == 0, "stop is idempotent")
        now.addTimeInterval(9)
        scheduler.deliverStale(beforeStop)
        expect(completions == 1, "late tick after stop cannot emit completion")
        store!.startMonitoringCountdown()
        expect(store!.goal.countdown?.isFinished == true && completions == 1, "restart after unmonitored expiry is silent")

        store!.restartCountdown()
        let beforeClear = scheduler.registrations.count - 1
        store!.clearCountdown()
        now.addTimeInterval(11)
        scheduler.deliverStale(beforeClear)
        expect(store!.goal.text == "One shared goal" && store!.goal.countdown == nil && completions == 1,
               "clear keeps text and rejects late completion")
        store!.startCountdown(seconds: 10)
        store!.save(text: " \n ")
        expect(store!.goal == OneGoal() && persistence.load() == nil && scheduler.activeCount == 0,
               "blank save deletes text, snapshot, and monitor")

        store!.save(text: "Release the owner")
        store!.startCountdown(seconds: 10)
        first.cancel()
        second.cancel()
        let releasedStore = { [weak store] in store }
        store = nil
        expect(releasedStore() == nil && scheduler.activeCount == 0, "teardown cancels without a callback retain cycle")
        now.addTimeInterval(11)
        for index in scheduler.registrations.indices { scheduler.deliverStale(index) }
        expect(completions == 1, "callbacks after teardown do nothing")

        let restored = OneGoalStore(persistence: persistence, scheduler: scheduler, clock: { now })
        restored.startMonitoringCountdown()
        expect(restored.goal.countdown?.isFinished == true && scheduler.activeCount == 0, "reconstruction silently handles expiry")
        restored.complete()
        persistence.save(Data("broken JSON".utf8))
        let recovered = OneGoalStore(persistence: persistence, scheduler: scheduler, clock: { now })
        expect(recovered.goal == OneGoal() && persistence.load() == nil, "component owns corrupt snapshot recovery")
    }

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        checks += 1
        XCTAssertTrue(condition(), message, file: file, line: line)
    }
}
