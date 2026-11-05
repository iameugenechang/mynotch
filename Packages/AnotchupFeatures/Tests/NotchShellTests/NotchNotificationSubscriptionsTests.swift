import Foundation
import XCTest
import NotchShell
import NotchShellAdapters

final class NotchNotificationSubscriptionsTests: XCTestCase {
    @MainActor
    func testNotificationDeliveryComposesDisplayRemovalAndRecreation() async {
        let center = NotificationCenter()
        let lock = Notification.Name("fixture.lock")
        let unlock = Notification.Name("fixture.unlock")
        let owner = NotchNotificationSubscriptions()
        var removed: [UUID] = []
        let displays = NotchDisplayLifecycle<UUID>(cancel: { _ in }, destroy: { removed.append($0) })
        func show() { displays.reconcile(ids: ["display"], make: { _ in UUID() }, update: { _, _ in }) }
        show()
        let original = displays.resources["display"]
        owner.observe(lock, center: center) { displays.cancelAll(); displays.removeAll() }
        owner.observe(unlock, center: center) { show() }
        center.post(name: lock, object: nil)
        await wait { displays.resources.isEmpty }
        XCTAssertEqual(removed, [original!])
        center.post(name: unlock, object: nil)
        await wait { !displays.resources.isEmpty }
        XCTAssertNotEqual(displays.resources["display"], original)
        owner.stop(); displays.stop()
        center.post(name: unlock, object: nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(displays.resources.isEmpty)
    }

    @MainActor
    func testQueuedDeliveryAndRegistrationsCannotOutliveOwner() async {
        let center = NotificationCenter()
        let name = Notification.Name("fixture.event")
        var calls = 0
        var owner: NotchNotificationSubscriptions? = NotchNotificationSubscriptions()
        owner?.observe(name, center: center) { calls += 1 }
        center.post(name: name, object: nil)
        XCTAssertEqual(calls, 0, "Always deferred")
        owner?.stop()
        owner?.observe(name, center: center) { calls += 1 }
        center.post(name: name, object: nil)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(calls, 0)
        owner = NotchNotificationSubscriptions()
        owner?.observe(name, center: center) { calls += 1 }
        center.post(name: name, object: nil)
        let released = { [weak owner] in owner }
        owner = nil
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(released())
        XCTAssertEqual(calls, 0)
    }

    @MainActor private func wait(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for notification delivery")
    }
}
