import Combine
import XCTest
import NotchShell
import NotchShellAdapters

@MainActor
final class ManualNotchDelayScheduler: NotchDelayScheduling {
    final class Registration {
        let deadline: Duration
        let action: @MainActor @Sendable () -> Void
        var active = true
        init(deadline: Duration, action: @escaping @MainActor @Sendable () -> Void) {
            self.deadline = deadline
            self.action = action
        }
    }
    private var now: Duration = .zero
    private(set) var registrations: [Registration] = []
    var activeCount: Int { registrations.filter(\.active).count }

    func schedule(after delay: Duration,
                  _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        let registration = Registration(deadline: now + max(.zero, delay), action: action)
        registrations.append(registration)
        return AnyCancellable { registration.active = false }
    }

    func advance(by duration: Duration) {
        now += duration
        // Snapshot: work scheduled by a callback waits for another advance.
        for registration in registrations where registration.active && registration.deadline <= now {
            registration.active = false
            registration.action()
        }
    }

    /// Adversarial delivery simulates a callback already queued at cancellation.
    func deliverStale(_ index: Int) { registrations[index].action() }
}

final class NotchInteractionLifetimeTests: XCTestCase {
    func testLanesAndCurrentStateAreIndependent() async {
        await MainActor.run {
            let scheduler = ManualNotchDelayScheduler()
            let owner = NotchInteractionLifetime(scheduler: scheduler)
            var state = NotchInteractionState(isOpen: true)
            var effects: [NotchDelayedActionSession.Effect] = []
            owner.schedule(.leave, after: .milliseconds(100), state: { state }, apply: { effects.append($0) })
            owner.schedule(.shortcutClose, after: .seconds(3), state: { state }, apply: { effects.append($0) })
            XCTAssertEqual(scheduler.activeCount, 2)
            owner.cancel(.hover)
            scheduler.deliverStale(0)
            XCTAssertEqual(scheduler.activeCount, 1)
            state.isEditorActive = true
            scheduler.advance(by: .seconds(3))
            XCTAssertTrue(effects.isEmpty, "delivery reads current protection")
            state.isEditorActive = false
            scheduler.deliverStale(1)
            XCTAssertTrue(effects.isEmpty, "blocked delivery is consumed")
            XCTAssertEqual(scheduler.activeCount, 0)
        }
    }

    func testReplacementAndReopenCancelTokensAndRejectQueuedDelivery() async {
        await MainActor.run {
            let scheduler = ManualNotchDelayScheduler()
            let owner = NotchInteractionLifetime(scheduler: scheduler)
            var effects: [NotchDelayedActionSession.Effect] = []
            let schedule = { owner.schedule(.shortcutClose, after: .seconds(3),
                state: { NotchInteractionState(isOpen: true) }, apply: { effects.append($0) }) }
            schedule()
            schedule()
            XCTAssertEqual(scheduler.activeCount, 1)
            scheduler.deliverStale(0)
            XCTAssertTrue(effects.isEmpty)
            owner.cancelAll()
            owner.cancelAll()
            XCTAssertEqual(scheduler.activeCount, 0)
            schedule()
            scheduler.deliverStale(1)
            scheduler.advance(by: .seconds(3))
            XCTAssertEqual(effects, [.close])
            scheduler.deliverStale(2)
            XCTAssertEqual(effects, [.close])
        }
    }

    func testRemovalIsTerminalAndRecreationDoesNotReviveOldWork() async {
        await MainActor.run {
            let scheduler = ManualNotchDelayScheduler()
            let old = NotchInteractionLifetime(scheduler: scheduler)
            var effects = 0
            let schedule: (NotchInteractionLifetime) -> Void = { owner in
                owner.schedule(.shortcutClose, after: .seconds(3),
                    state: { NotchInteractionState(isOpen: true) }, apply: { _ in effects += 1 })
            }
            schedule(old)
            old.invalidate()
            old.invalidate()
            schedule(old)
            XCTAssertTrue(old.isInvalidated)
            XCTAssertEqual(scheduler.registrations.count, 1, "late host events cannot schedule")
            XCTAssertEqual(scheduler.activeCount, 0)
            let replacement = NotchInteractionLifetime(scheduler: scheduler)
            schedule(replacement)
            scheduler.deliverStale(0)
            XCTAssertEqual(effects, 0)
            scheduler.advance(by: .seconds(3))
            XCTAssertEqual(effects, 1)
        }
    }

    func testTwoDisplayOwnersShareAnAdapterWithoutSharingLifetime() async {
        await MainActor.run {
            let scheduler = ManualNotchDelayScheduler()
            let first = NotchInteractionLifetime(scheduler: scheduler)
            let second = NotchInteractionLifetime(scheduler: scheduler)
            var effects: [String] = []
            first.schedule(.shortcutClose, after: .seconds(3),
                state: { NotchInteractionState(isOpen: true) }, apply: { _ in effects.append("first") })
            second.schedule(.shortcutClose, after: .seconds(3),
                state: { NotchInteractionState(isOpen: true) }, apply: { _ in effects.append("second") })
            first.invalidate()
            scheduler.deliverStale(0)
            scheduler.advance(by: .seconds(3))
            XCTAssertEqual(effects, ["second"])
        }
    }

    func testDeliveryRemovesOldWorkBeforeReentrantEffect() async {
        await MainActor.run {
            let scheduler = ManualNotchDelayScheduler()
            let owner = NotchInteractionLifetime(scheduler: scheduler)
            var effects = 0
            owner.schedule(.shortcutClose, after: .zero, state: { NotchInteractionState(isOpen: true) }) { [weak owner] _ in
                effects += 1
                owner?.cancelAll()
                owner?.schedule(.shortcutClose, after: .zero,
                    state: { NotchInteractionState(isOpen: true) }, apply: { _ in effects += 1 })
            }
            scheduler.advance(by: .zero)
            XCTAssertEqual(effects, 1)
            XCTAssertEqual(scheduler.activeCount, 1, "old delivery must not erase newly scheduled work")
            scheduler.deliverStale(0)
            XCTAssertEqual(effects, 1)
            scheduler.advance(by: .zero)
            XCTAssertEqual(effects, 2)
        }
    }

    func testOwnerReleaseCancelsTokensAndReleasesCallbacks() async {
        await MainActor.run {
            final class Probe {}
            let scheduler = ManualNotchDelayScheduler()
            var owner: NotchInteractionLifetime? = NotchInteractionLifetime(scheduler: scheduler)
            let releasedOwner = { [weak owner] in owner }
            var probe: Probe? = Probe()
            let releasedProbe = { [weak probe] in probe }
            owner?.schedule(.shortcutClose, after: .seconds(3),
                state: { NotchInteractionState(isOpen: true) }, apply: { [probe] _ in
                    _ = probe
                    XCTFail("released owner must not deliver")
                })
            probe = nil
            XCTAssertNotNil(releasedProbe())
            owner = nil
            XCTAssertNil(releasedOwner())
            XCTAssertNil(releasedProbe())
            XCTAssertEqual(scheduler.activeCount, 0)
            scheduler.deliverStale(0)
        }
    }

    func testCancellationReleasesCallbacksWithoutReadingState() async {
        await MainActor.run {
            final class Probe {}
            let scheduler = ManualNotchDelayScheduler()
            let owner = NotchInteractionLifetime(scheduler: scheduler)
            var reader: Probe? = Probe()
            var effect: Probe? = Probe()
            let releasedReader = { [weak reader] in reader }
            let releasedEffect = { [weak effect] in effect }
            owner.schedule(.shortcutClose, after: .seconds(3), state: { [reader] in
                _ = reader
                XCTFail("canceled work must not read host state")
                return NotchInteractionState(isOpen: true)
            }, apply: { [effect] _ in
                _ = effect
                XCTFail("canceled work must not apply effects")
            })
            reader = nil
            effect = nil
            XCTAssertNotNil(releasedReader())
            XCTAssertNotNil(releasedEffect())
            owner.cancel(.shortcut)
            XCTAssertNil(releasedReader())
            XCTAssertNil(releasedEffect())
            XCTAssertEqual(scheduler.activeCount, 0)
            scheduler.deliverStale(0)
            XCTAssertFalse(owner.isInvalidated)
        }
    }

    @MainActor
    func testRealSchedulerCompositionDeliversAndCancels() async throws {
        let owner = NotchInteractionLifetime(scheduler: TaskNotchDelayScheduler())
        let delivered = expectation(description: "real one-shot reaches component output")
        owner.schedule(.shortcutClose, after: .milliseconds(10),
            state: { NotchInteractionState(isOpen: true) }, apply: { _ in delivered.fulfill() })
        await fulfillment(of: [delivered], timeout: 3)
        owner.schedule(.shortcutClose, after: .zero,
            state: { NotchInteractionState(isOpen: true) }, apply: { _ in XCTFail("invalidated delivery") })
        owner.invalidate()
        try await Task.sleep(for: .milliseconds(50))
    }
}
