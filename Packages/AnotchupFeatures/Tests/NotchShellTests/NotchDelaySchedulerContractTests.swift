import Combine
import XCTest
import NotchShell
import NotchShellAdapters

final class NotchDelaySchedulerContractTests: XCTestCase {
    @MainActor
    func testManualAdapterConformance() async {
        let scheduler = ManualNotchDelayScheduler()
        await check(scheduler) { _ in scheduler.advance(by: .seconds(1)) }
    }

    @MainActor
    func testTaskAdapterConformance() async {
        await check(TaskNotchDelayScheduler()) { ready in
            if let ready {
                // A bounded wait for delivery, not an exact timer precision assertion.
                for _ in 0..<300 {
                    if ready() { return }
                    try? await Task.sleep(for: .milliseconds(10))
                }
            } else {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    @MainActor
    private func check(_ scheduler: any NotchDelayScheduling,
                       advance: @MainActor (_ ready: (@MainActor () -> Bool)?) async -> Void) async {
        var delivered = 0
        let token = scheduler.schedule(after: .milliseconds(10)) { delivered += 1 }
        XCTAssertEqual(delivered, 0, "never inline")
        await advance({ delivered == 1 })
        XCTAssertEqual(delivered, 1)
        await advance(nil)
        XCTAssertEqual(delivered, 1, "one-shot, not repeating")
        token.cancel()
        token.cancel()

        let canceled = scheduler.schedule(after: .zero) { XCTFail("canceled token delivered") }
        canceled.cancel()
        canceled.cancel()
        var released: AnyCancellable? = scheduler.schedule(after: .zero) { XCTFail("released token delivered") }
        XCTAssertNotNil(released)
        released = nil
        await advance(nil)

        var zeroDelivered = false
        let zero = scheduler.schedule(after: .zero) { zeroDelivered = true }
        XCTAssertFalse(zeroDelivered, "zero-delay delivery is also deferred")
        await advance({ zeroDelivered })
        XCTAssertTrue(zeroDelivered)

        var negativeDelivered = false
        let negative = scheduler.schedule(after: .seconds(-1)) { negativeDelivered = true }
        XCTAssertFalse(negativeDelivered)
        await advance({ negativeDelivered })
        XCTAssertTrue(negativeDelivered, "negative delay behaves as zero")

        let independent = scheduler.schedule(after: .zero) { delivered += 1 }
        zero.cancel()
        negative.cancel()
        await advance({ delivered == 2 })
        XCTAssertEqual(delivered, 2, "canceling another token does not cancel this one")
        withExtendedLifetime([token, canceled, zero, negative, independent]) {}
    }
}
