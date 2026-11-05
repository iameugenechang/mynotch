import XCTest
import NotchShell

final class NotchDelayedActionSessionTests: XCTestCase {
    // Characterizes AnotchupViewModel.close: only sharing and editing block a
    // general close. Battery/hover protection belongs to hover-triggered closes.
    func testGeneralCloseProtection() {
        for sharing in [false, true] {
            for editing in [false, true] {
                let state = NotchInteractionState(isOpen: true, isHovering: true,
                    isBatteryPopoverActive: true, isSharing: sharing, isEditorActive: editing)
                XCTAssertEqual(state.canClose, !sharing && !editing)
            }
        }
    }

    func testHoverCloseConditions() {
        for open in [false, true] {
            for hovering in [false, true] {
                for battery in [false, true] {
                    for sharing in [false, true] {
                        for editing in [false, true] {
                            var session = NotchDelayedActionSession()
                            let ticket = session.schedule(.closeAfterProtection)
                            let state = NotchInteractionState(isOpen: open, isHovering: hovering,
                                isBatteryPopoverActive: battery, isSharing: sharing, isEditorActive: editing)
                            let expected = open && !hovering && !battery && !sharing && !editing
                            XCTAssertEqual(session.fire(ticket, state: state), expected ? .close : nil)
                        }
                    }
                }
            }
        }
    }

    func testHoverOpenConditions() {
        for open in [false, true] {
            for hovering in [false, true] {
                for goalControl in [false, true] {
                    for preview in [false, true] {
                        for enabled in [false, true] {
                            var session = NotchDelayedActionSession()
                            let ticket = session.schedule(.open)
                            let state = NotchInteractionState(isOpen: open, isHovering: hovering,
                                isHoveringGoalControl: goalControl, isPreviewVisible: preview, opensOnHover: enabled)
                            let expected = !open && hovering && !goalControl && !preview && enabled
                            XCTAssertEqual(session.fire(ticket, state: state), expected ? .open : nil)
                        }
                    }
                }
            }
        }
    }

    func testHoverExitClearsVisualHoverEvenWhenCloseIsProtected() {
        for open in [false, true] {
            for battery in [false, true] {
                for sharing in [false, true] {
                    for editing in [false, true] {
                        var session = NotchDelayedActionSession()
                        let ticket = session.schedule(.leave)
                        let state = NotchInteractionState(isOpen: open, isHovering: true,
                            isBatteryPopoverActive: battery, isSharing: sharing, isEditorActive: editing)
                        XCTAssertEqual(session.fire(ticket, state: state),
                            .endHover(shouldClose: open && !battery && !sharing && !editing))
                    }
                }
            }
        }
    }

    func testReplacementRejectsAlreadyQueuedCallbacksAndConsumesOnlyOnce() {
        var session = NotchDelayedActionSession()
        let old = session.schedule(.leave)
        let current = session.schedule(.open)
        let state = NotchInteractionState(isOpen: false, isHovering: true)
        XCTAssertNil(session.fire(old, state: state))
        XCTAssertEqual(session.fire(current, state: state), .open)
        XCTAssertNil(session.fire(current, state: state))
    }

    func testCancellationIsIdempotentAndAllowsNewRequests() {
        var session = NotchDelayedActionSession()
        let ticket = session.schedule(.leave)
        session.cancel()
        session.cancel()
        let resumed = session.schedule(.closeAfterProtection)
        XCTAssertNil(session.fire(ticket, state: NotchInteractionState(isOpen: true)))
        XCTAssertEqual(session.fire(resumed, state: NotchInteractionState(isOpen: true)), .close)
    }

    func testRecreatedDisplayRejectsPreviousLifetimeTicket() {
        var session = NotchDelayedActionSession()
        let previousLifetime = session.schedule(.leave)
        session = NotchDelayedActionSession()
        let current = session.schedule(.closeAfterProtection)
        let state = NotchInteractionState(isOpen: true)
        XCTAssertNil(session.fire(previousLifetime, state: state))
        XCTAssertEqual(session.fire(current, state: state), .close)
    }

    func testProtectionIsReadAtDeliveryAndBlockedWorkDoesNotRevive() {
        var session = NotchDelayedActionSession()
        let ticket = session.schedule(.closeAfterProtection)
        XCTAssertNil(session.fire(ticket, state: NotchInteractionState(isOpen: true, isEditorActive: true)))
        XCTAssertNil(session.fire(ticket, state: NotchInteractionState(isOpen: true)))
        let next = session.schedule(.closeAfterProtection)
        XCTAssertEqual(session.fire(next, state: NotchInteractionState(isOpen: true)), .close)
    }

    func testDisplaySessionsCannotConsumeOrCancelEachOthersWork() {
        var first = NotchDelayedActionSession()
        var second = NotchDelayedActionSession()
        let firstTicket = first.schedule(.leave)
        let secondTicket = second.schedule(.closeAfterProtection)
        let state = NotchInteractionState(isOpen: true)
        XCTAssertNil(first.fire(secondTicket, state: state))
        XCTAssertNil(second.fire(firstTicket, state: state))
        first.cancel()
        XCTAssertEqual(second.fire(secondTicket, state: state), .close)
        XCTAssertNil(first.fire(firstTicket, state: state))
    }
}
