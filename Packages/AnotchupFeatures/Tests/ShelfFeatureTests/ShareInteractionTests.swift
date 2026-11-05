import ShelfFeature
import XCTest

final class ShareInteractionTests: XCTestCase {
    func testPickerToServiceCountsOnceAndRetainsUntilCompletion() async {
        await MainActor.run {
            var protection = 0
            var cleanups = 0
            let share = ShareInteraction(onBegin: { protection += 1 }, onFinish: { protection -= 1 }, cleanup: { cleanups += 1 })
            share.beginPicker()
            share.beginPicker()
            share.beginService()
            share.beginService()
            share.pickerCanceled()
            XCTAssertEqual(protection, 1)
            XCTAssertEqual(cleanups, 0)
            share.finish()
            share.finish()
            share.beginService()
            XCTAssertEqual(protection, 0)
            XCTAssertEqual(cleanups, 1)
        }
    }

    func testIndependentOperationsAndCancellationBeforeStart() async {
        await MainActor.run {
            var protection = 0
            var cleanups = 0
            let make = { ShareInteraction(onBegin: { protection += 1 }, onFinish: { protection -= 1 }, cleanup: { cleanups += 1 }) }
            let first = make(), second = make(), unused = make()
            first.beginPicker()
            second.beginService()
            unused.finish()
            XCTAssertEqual(protection, 2)
            first.pickerCanceled()
            XCTAssertEqual(protection, 1)
            second.finish()
            XCTAssertEqual(protection, 0)
            XCTAssertEqual(cleanups, 3)
        }
    }
}
