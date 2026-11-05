import NotchShell
import XCTest

final class NotchDisplayLifecycleTests: XCTestCase {
    @MainActor
    func testCreationRemovalReassignmentAndTerminalStop() {
        var created: [String] = [], destroyed: [String] = [], canceled: [String] = []
        let host = NotchDisplayLifecycle<String>(cancel: { canceled.append($0) }, destroy: { destroyed.append($0) })
        func update(_ ids: Set<String>) {
            host.reconcile(ids: ids, make: { created.append($0); return $0 }, update: { _, _ in })
        }
        update(["a", "b"])
        update(["a", "b"])
        XCTAssertEqual(created, ["a", "b"])
        host.cancelAll()
        XCTAssertEqual(Set(canceled), ["a", "b"])
        update(["b", "c"])
        XCTAssertEqual(destroyed, ["a"])
        XCTAssertEqual(Set(host.resources.keys), ["b", "c"])
        host.stop()
        host.stop()
        update(["a"])
        XCTAssertTrue(host.resources.isEmpty)
        XCTAssertEqual(Set(destroyed), ["a", "b", "c"])
        XCTAssertEqual(destroyed.count, 3)
    }

    @MainActor
    func testLockUnlockAndMissingDisplayPlan() {
        typealias Host = NotchDisplayLifecycle<String>
        XCTAssertEqual(Host.desiredIDs(available: ["a", "b"], selected: "a", allDisplays: false, locked: false, showOnLockScreen: false), ["a"])
        XCTAssertEqual(Host.desiredIDs(available: ["a", "b"], selected: "missing", allDisplays: false, locked: false, showOnLockScreen: true), [])
        XCTAssertEqual(Host.desiredIDs(available: ["a", "b"], selected: nil, allDisplays: true, locked: true, showOnLockScreen: false), [])
        XCTAssertEqual(Host.desiredIDs(available: ["a", "b"], selected: nil, allDisplays: true, locked: true, showOnLockScreen: true), ["a", "b"])
        XCTAssertEqual(Host.desiredIDs(available: [], selected: "a", allDisplays: true, locked: false, showOnLockScreen: false), [])
    }

    @MainActor
    func testRemovalCancelsRealOwnersAndSharedEditorRegistration() {
        struct Resource { let id: UUID; let lifetime: NotchInteractionLifetime }
        let navigation = NotchNavigation()
        let host = NotchDisplayLifecycle<Resource>(cancel: { $0.lifetime.cancelAll() }, destroy: {
            $0.lifetime.invalidate(); navigation.remove($0.id)
        })
        let scheduler = ManualNotchDelayScheduler()
        var effects = 0
        host.reconcile(ids: ["a", "b"], make: { _ in
            let id = UUID()
            navigation.register(id)
            return Resource(id: id, lifetime: NotchInteractionLifetime(scheduler: scheduler))
        }, update: { _, resource in
            resource.lifetime.schedule(.shortcutClose, after: .seconds(3), state: { NotchInteractionState(isOpen: true) }, apply: { _ in effects += 1 })
        })
        let removed = host.resources["a"]!
        navigation.requestEditor(true, on: removed.id)
        host.removeAll()
        XCTAssertTrue(removed.lifetime.isInvalidated)
        XCTAssertFalse(navigation.resignedKey(removed.id))
        scheduler.advance(by: .seconds(4))
        XCTAssertEqual(effects, 0)
    }

    func testGeometryPreservesCutoutAndPointerPolicies() {
        let screen = CGRect(x: -1000, y: -500, width: 800, height: 600)
        XCTAssertEqual(NotchGeometry.origin(screen: screen, window: CGSize(width: 200, height: 80)), CGPoint(x: -700, y: 20))
        XCTAssertTrue(NotchGeometry.contains(CGPoint(x: -700, y: 20), screen: screen, notch: CGSize(width: 200, height: 80)))
        XCTAssertFalse(NotchGeometry.contains(CGPoint(x: -701, y: 20), screen: screen, notch: CGSize(width: 200, height: 80)))
        XCTAssertEqual(NotchGeometry.closedHeight(height: 32, hide: true, hasCutout: false), 0)
        XCTAssertEqual(NotchGeometry.closedHeight(height: 32, hide: true, hasCutout: true), 32)
        XCTAssertEqual(NotchGeometry.chinHeight(menuBar: 40, closed: 32, hiddenTitleBar: true, isOpen: false), 8)
        XCTAssertEqual(NotchGeometry.chinHeight(menuBar: 40, closed: 32, hiddenTitleBar: true, isOpen: true), 0)
    }
}
