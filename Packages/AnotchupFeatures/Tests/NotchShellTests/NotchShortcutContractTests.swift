import XCTest
import NotchShell

final class NotchShortcutContractTests: XCTestCase {
    func testShortcutCloseUsesGeneralNotHoverProtection() {
        for open in [false, true] {
            for sharing in [false, true] {
                for editing in [false, true] {
                    for hovering in [false, true] {
                        for battery in [false, true] {
                            var lane = NotchDelayedActionSession()
                            let ticket = lane.schedule(.shortcutClose)
                            let state = NotchInteractionState(isOpen: open, isHovering: hovering,
                                isBatteryPopoverActive: battery, isSharing: sharing, isEditorActive: editing)
                            XCTAssertEqual(lane.fire(ticket, state: state),
                                open && !sharing && !editing ? .close : nil)
                        }
                    }
                }
            }
        }
    }

    func testBlockedAutoCloseIsConsumedInsteadOfClosingAfterEditingEnds() {
        var lane = NotchDelayedActionSession()
        let ticket = lane.schedule(.shortcutClose)
        XCTAssertNil(lane.fire(ticket, state: NotchInteractionState(isOpen: true, isEditorActive: true)))
        XCTAssertNil(lane.fire(ticket, state: NotchInteractionState(isOpen: true)))
    }

    func testCanceledAutoCloseCannotCloseAReopenedNotchOrConsumeNewWork() {
        var lane = NotchDelayedActionSession()
        let old = lane.schedule(.shortcutClose)
        lane.cancel()
        let current = lane.schedule(.shortcutClose)
        let state = NotchInteractionState(isOpen: true)
        XCTAssertNil(lane.fire(old, state: state))
        XCTAssertEqual(lane.fire(current, state: state), .close)
        XCTAssertNil(lane.fire(current, state: state))
    }

    func testAutoCloseOnOneDisplayDoesNotReplaceAnotherDisplaysDeadline() {
        var first = NotchDelayedActionSession()
        var second = NotchDelayedActionSession()
        let firstTicket = first.schedule(.shortcutClose)
        let secondTicket = second.schedule(.shortcutClose)
        let state = NotchInteractionState(isOpen: true)
        XCTAssertNil(first.fire(secondTicket, state: state))
        XCTAssertEqual(first.fire(firstTicket, state: state), .close)
        XCTAssertEqual(second.fire(secondTicket, state: state), .close)
    }

    func testPointerReentryCancelsOnlyTheHoverLane() {
        var hover = NotchDelayedActionSession()
        var shortcut = NotchDelayedActionSession()
        let leave = hover.schedule(.leave)
        let autoClose = shortcut.schedule(.shortcutClose)
        hover.cancel()
        let state = NotchInteractionState(isOpen: true, isHovering: true)
        XCTAssertNil(hover.fire(leave, state: state))
        XCTAssertEqual(shortcut.fire(autoClose, state: state), .close)
    }

    func testRecreatedOwnerRejectsPreviousLifetimeAutoClose() {
        var lane = NotchDelayedActionSession()
        let old = lane.schedule(.shortcutClose)
        lane = NotchDelayedActionSession()
        let current = lane.schedule(.shortcutClose)
        let state = NotchInteractionState(isOpen: true)
        XCTAssertNil(lane.fire(old, state: state))
        XCTAssertEqual(lane.fire(current, state: state), .close)
    }
}
