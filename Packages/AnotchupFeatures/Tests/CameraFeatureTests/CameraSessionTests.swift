import CameraFeature
import Combine
import XCTest

@MainActor
private final class Device: CameraDevice {
    var authorization: CameraAuthorization = .allowed
    var isAvailable = true
    var starts = 0, stops = 0, requests = 0
    var startAction: (() async throws -> Void)?
    var requestAction: (() async -> CameraAuthorization)?
    func requestAuthorization() async -> CameraAuthorization {
        requests += 1
        authorization = await requestAction?() ?? authorization
        return authorization
    }
    func start() async throws { starts += 1; try await startAction?() }
    func stop() async { stops += 1 }
}

final class CameraSessionTests: XCTestCase {
    @MainActor
    private func reach(_ phase: CameraPhase, session: CameraSession, action: () -> Void) async {
        let done = expectation(description: "reach \(phase)")
        let observation = session.$phase.filter { $0 == phase }.prefix(1).sink { _ in done.fulfill() }
        action()
        await fulfillment(of: [done], timeout: 1)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testStartDoesNotPromptAndDeniedOrMissingNeverAcquiresDevice() {
        let device = Device()
        device.authorization = .denied
        let session = CameraSession(device: device)
        session.start()
        XCTAssertEqual(session.phase, .denied)
        device.authorization = .allowed
        device.isAvailable = false
        session.start()
        XCTAssertEqual(session.phase, .unavailable)
        XCTAssertEqual(device.starts, 0)
        XCTAssertEqual(device.requests, 0)
    }

    @MainActor
    func testRepeatedStartStopAndTerminalShutdown() async {
        let device = Device(), session: CameraSession
        session = CameraSession(device: device)
        await reach(.running, session: session) { session.start(); session.start() }
        XCTAssertEqual(device.starts, 1)
        await reach(.idle, session: session) { session.stop(); session.stop() }
        XCTAssertEqual(device.stops, 1)
        await reach(.running, session: session) { session.start() }
        await reach(.stopped, session: session) { session.shutdown() }
        session.start()
        await session.requestAuthorization()
        XCTAssertEqual(device.starts, 2)
        XCTAssertEqual(device.stops, 2)
        XCTAssertEqual(device.requests, 0)
    }

    @MainActor
    func testStopDuringAcquisitionReleasesLateResource() async {
        let device = Device()
        var completion: CheckedContinuation<Void, Never>?
        let began = expectation(description: "start suspended")
        device.startAction = { await withCheckedContinuation { completion = $0; began.fulfill() } }
        let session = CameraSession(device: device)
        session.start()
        await fulfillment(of: [began], timeout: 1)
        session.stop()
        await reach(.idle, session: session) { completion?.resume() }
        XCTAssertEqual(device.starts, 1)
        XCTAssertEqual(device.stops, 1)
    }

    @MainActor
    func testShutdownDuringAcquisitionIsTerminal() async {
        let device = Device()
        var completion: CheckedContinuation<Void, Never>?
        let began = expectation(description: "start suspended")
        device.startAction = { await withCheckedContinuation { completion = $0; began.fulfill() } }
        let session = CameraSession(device: device)
        session.start()
        await fulfillment(of: [began], timeout: 1)
        session.shutdown()
        await reach(.stopped, session: session) { completion?.resume() }
        session.start()
        XCTAssertEqual(device.starts, 1)
        XCTAssertEqual(device.stops, 1)
    }

    @MainActor
    func testFailedAcquisitionCleansUpAndCanRetry() async {
        enum Failure: Error { case setup }
        let device = Device()
        device.startAction = { throw Failure.setup }
        let session = CameraSession(device: device)
        await reach(.failed("setup"), session: session) { session.start() }
        XCTAssertEqual(device.stops, 1)
        device.startAction = nil
        await reach(.running, session: session) { session.start() }
        await reach(.stopped, session: session) { session.shutdown() }
    }

    @MainActor
    func testConcurrentAuthorizationRequestsAreCoalescedAndNeverStartCapture() async {
        let device = Device()
        device.authorization = .unknown
        var completion: CheckedContinuation<CameraAuthorization, Never>?
        let began = expectation(description: "authorization pending")
        device.requestAction = { await withCheckedContinuation { completion = $0; began.fulfill() } }
        let session = CameraSession(device: device)
        let first = Task { await session.requestAuthorization() }
        await fulfillment(of: [began], timeout: 1)
        let secondStarted = expectation(description: "second request entered")
        let second = Task { secondStarted.fulfill(); await session.requestAuthorization() }
        await fulfillment(of: [secondStarted], timeout: 1)
        XCTAssertTrue(session.requestingAuthorization)
        completion?.resume(returning: .allowed)
        await first.value
        await second.value
        XCTAssertEqual(device.requests, 1)
        XCTAssertEqual(device.starts, 0)
        XCTAssertEqual(session.authorization, .allowed)
        XCTAssertFalse(session.requestingAuthorization)
        session.shutdown()
    }
}
