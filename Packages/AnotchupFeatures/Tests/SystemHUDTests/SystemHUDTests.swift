import SystemHUD
import XCTest

final class SystemHUDTests: XCTestCase {
    func testDecoderRejectsUnknownKindsInvalidValuesAndShapes() throws {
        for kind in ["volume", "brightness", "backlight", "mic"] {
            let json = #"{"show":true,"type":"KIND","value":"0.5","icon":"test"}"#.replacingOccurrences(of: "KIND", with: kind)
            XCTAssertEqual(try HUDMessage.decode(Data(json.utf8)).value, 0.5)
        }
        for value in ["NaN", "inf", "-0.1", "1.01", "abc", ""] {
            let json = #"{"show":true,"type":"volume","value":"VALUE","icon":""}"#.replacingOccurrences(of: "VALUE", with: value)
            XCTAssertThrowsError(try HUDMessage.decode(Data(json.utf8)))
        }
        XCTAssertThrowsError(try HUDMessage.decode(Data(#"{"show":true,"type":"unknown","value":"0","icon":""}"#.utf8)))
        XCTAssertThrowsError(try HUDMessage.decode(Data("{}".utf8)))
    }

    @MainActor
    func testAuthorizationCancellationCannotAcquireTap() async {
        var pending: CheckedContinuation<Bool, Never>?
        var prompts: [Bool] = [], acquired = 0, released = 0
        let activation = HUDActivation(authorize: { prompt in
            prompts.append(prompt)
            return await withCheckedContinuation { pending = $0 }
        }, activate: { acquired += 1; return true }, deactivate: { released += 1 }, rejected: {})
        activation.setEnabled(true)
        for _ in 0..<200 where pending == nil { await Task.yield() }
        XCTAssertNotNil(pending)
        activation.setEnabled(false)
        pending?.resume(returning: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(prompts, [false])
        XCTAssertEqual(acquired, 0)
        XCTAssertEqual(released, 1)
        XCTAssertFalse(activation.isActive)
        activation.stop()
        activation.setEnabled(true, promptIfNeeded: true)
        XCTAssertEqual(prompts, [false])
    }

    @MainActor
    func testDenialRevocationAndExplicitPrompt() async {
        var granted = true, acquired = 0, rejected = 0
        var prompts: [Bool] = []
        let activation = HUDActivation(authorize: { prompts.append($0); return granted },
            activate: { acquired += 1; return true }, deactivate: {}, rejected: { rejected += 1 })
        activation.setEnabled(true, promptIfNeeded: true)
        for _ in 0..<200 where !activation.isActive { await Task.yield() }
        XCTAssertTrue(activation.isActive)
        granted = false
        activation.setEnabled(true)
        for _ in 0..<200 where rejected == 0 { await Task.yield() }
        XCTAssertFalse(activation.isActive)
        XCTAssertEqual(acquired, 1)
        XCTAssertEqual(rejected, 1)
        XCTAssertEqual(prompts, [true, false])
        activation.stop()
    }

    @MainActor
    func testConnectionReusesReplacesAndRejectsOldDisconnects() throws {
        var callbacks: [@MainActor () -> Void] = []
        var closed: [Int] = []
        let owner = ConnectionOwner<Int>(make: { callbacks.append($0); return callbacks.count }, close: { closed.append($0) })
        let first = try owner.acquire()
        XCTAssertEqual(try owner.acquire().id, first.id)
        callbacks[0]()
        let second = try owner.acquire()
        XCTAssertNotEqual(first.id, second.id)
        callbacks[0]()
        XCTAssertTrue(owner.isCurrent(second))
        XCTAssertEqual(closed, [1])
        owner.stop()
        owner.stop()
        XCTAssertEqual(closed, [1, 2])
        XCTAssertThrowsError(try owner.acquire())
    }

    @MainActor
    func testConnectionDiscardsLateResultsAndRetriesFactoryFailures() async throws {
        enum Failure: Error { case unavailable }
        var available = false
        let owner = ConnectionOwner<Int>(make: { _ in
            if !available { throw Failure.unavailable }
            return 1
        }, close: { _ in })
        XCTAssertThrowsError(try owner.acquire())
        available = true
        do {
            _ = try await owner.perform { _ in owner.disconnect(); _ = try owner.acquire(); return true }
            XCTFail("old connection result escaped")
        } catch ConnectionOwner<Int>.Failure.stale {} catch { XCTFail("\(error)") }
        let value = try await owner.perform { $0 }
        XCTAssertEqual(value, 1)
        owner.stop()
    }
}
