import XCTest
import NotchShell

final class NotchPresentationContractTests: XCTestCase {
    func testDragConsumesDropAndRespectsCloseProtection() async {
        await MainActor.run {
            for dropped in [false, true] {
                for sharing in [false, true] {
                    for editor in [false, true] {
                        var session = NotchDelayedActionSession()
                        let ticket = session.schedule(.dragExit)
                        let effect = session.fire(ticket, state: .init(isOpen: true,
                            isSharing: sharing, isEditorActive: editor, hasPendingDrop: dropped))
                        XCTAssertEqual(effect, .endDrag(shouldClose: !dropped && !sharing && !editor))
                        XCTAssertNil(session.fire(ticket, state: .init(isOpen: true)))
                    }
                }
            }
        }
    }
    func testResizeRechecksOpenAndPreviewState() async {
        await MainActor.run {
            for opened in [false, true] {
                for preview in [false, true] {
                    var session = NotchDelayedActionSession()
                    let ticket = session.schedule(.resize)
                    XCTAssertEqual(session.fire(ticket, state: .init(isOpen: opened, isPreviewVisible: preview)),
                                   !opened && !preview ? .resize : nil)
                }
            }
        }
    }
    func testPresentationLanesReplaceIndependentlyAndTeardownRejectsAllQueuedWork() async {
        await MainActor.run {
            let scheduler = ManualNotchDelayScheduler()
            let owner = NotchInteractionLifetime(scheduler: scheduler)
            var effects: [NotchDelayedActionSession.Effect] = []
            @MainActor func schedule(_ request: NotchDelayedActionSession.Request) {
                owner.schedule(request, after: .seconds(1),
                    state: { .init(isOpen: false, isPreviewVisible: true) },
                    apply: { effects.append($0) })
            }
            schedule(.hideCompactPreview)
            schedule(.hideExpandedPreview)
            schedule(.dragExit)
            schedule(.resize)
            schedule(.hideCompactPreview)
            XCTAssertEqual(scheduler.activeCount, 4)
            scheduler.deliverStale(0)
            XCTAssertTrue(effects.isEmpty)
            owner.cancel(.drag)
            scheduler.advance(by: .seconds(1))
            XCTAssertEqual(effects, [.hidePreview, .hidePreview])
            XCTAssertEqual(scheduler.activeCount, 0)
            schedule(.hideExpandedPreview)
            schedule(.resize)
            owner.invalidate()
            for i in scheduler.registrations.indices { scheduler.deliverStale(i) }
            XCTAssertEqual(effects.count, 2)
        }
    }
}
