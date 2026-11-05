import Combine
import Foundation
import XCTest
import MediaFeature

private final class ControlledProvider: MediaProvider {
    let snapshots = PassthroughSubject<PlaybackState, Never>()
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { snapshots.eraseToAnyPublisher() }
    var supportsVolumeControl = true
    var supportsFavorite = false
    var commands: [MediaCommand] = []
    var onPlay: (() async -> Void)?
    var stopCount = 0
    func stop() { stopCount += 1 }
    func play() async { commands.append(.play); await onPlay?() }
    func pause() async { commands.append(.pause) }
    func setFavorite(_ value: Bool) async { commands.append(.favorite(value)) }
    func seek(to value: Double) async { commands.append(.seek(value)) }
    func nextTrack() async { commands.append(.next) }
    func previousTrack() async { commands.append(.previous) }
    func togglePlay() async { commands.append(.togglePlay) }
    func toggleShuffle() async { commands.append(.toggleShuffle) }
    func toggleRepeat() async { commands.append(.toggleRepeat) }
    func setVolume(_ value: Double) async { commands.append(.volume(value)) }
    func updatePlaybackInfo() async { commands.append(.refresh) }
    func isActive() -> Bool { true }
}

final class MediaSessionTests: XCTestCase {
    @MainActor
    func testQueuedPlaybackFromReplacedProviderCannotOverwriteCurrentState() async {
        let a = ControlledProvider(), b = ControlledProvider(), session = MediaSession()
        let delivered = expectation(description: "current provider delivered")
        var received: [String] = []
        let observation = session.$state.compactMap { $0 }.sink {
            received.append($0.title)
            if $0.title == "B" { delivered.fulfill() }
        }
        session.select(a)
        a.snapshots.send(.init(bundleIdentifier: "a", title: "A"))
        session.select(b)
        b.snapshots.send(.init(bundleIdentifier: "b", title: "B"))
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(received, ["B"])
        XCTAssertEqual(session.state?.bundleIdentifier, "b")
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testRevisionsRejectOldArtworkLyricsAndTeardownResults() async {
        let provider = ControlledProvider(), session = MediaSession()
        session.select(provider)
        func publish(_ state: PlaybackState) async {
            let delivered = expectation(description: "snapshot delivered")
            let observation = session.$state.compactMap { $0 }.dropFirst(session.state == nil ? 0 : 1).sink { _ in delivered.fulfill() }
            provider.snapshots.send(state)
            await fulfillment(of: [delivered], timeout: 1)
            withExtendedLifetime(observation) {}
        }
        var state = PlaybackState(bundleIdentifier: "a", title: "track")
        await publish(state)
        let trackRevision = session.revision
        state.currentTime = 10
        state.volume = 0.9
        await publish(state)
        XCTAssertTrue(session.isCurrent(trackRevision), "position and volume do not invalidate content")
        state.title = "next"
        await publish(state)
        XCTAssertFalse(session.isCurrent(trackRevision))
        let nextRevision = session.revision
        state.artwork = Data([1, 2])
        await publish(state)
        XCTAssertFalse(session.isCurrent(nextRevision))
        let artworkRevision = session.revision
        session.stop()
        XCTAssertFalse(session.isCurrent(artworkRevision))
        XCTAssertNil(session.provider)
        session.select(provider)
        XCTAssertNil(session.provider, "stop is terminal")
    }

    @MainActor
    func testCapabilitiesValidationAndCommandSubmission() async {
        let provider = ControlledProvider(), session = MediaSession()
        let absent = await session.send(.play)
        XCTAssertEqual(absent, .unavailable)
        session.select(provider)
        let unsupported = await session.send(.favorite(true))
        let invalid = await session.send(.volume(.nan))
        let invalidSeek = await session.send(.seek(-1))
        XCTAssertEqual(unsupported, .unsupported)
        XCTAssertEqual(invalid, .invalidArgument)
        XCTAssertEqual(invalidSeek, .invalidArgument)
        XCTAssertTrue(provider.commands.isEmpty)
        let clamped = await session.send(.volume(5))
        XCTAssertEqual(clamped, .submitted)
        XCTAssertEqual(provider.commands, [.volume(1)])
        provider.supportsVolumeControl = false
        let disabled = await session.send(.volume(0.5))
        XCTAssertEqual(disabled, .unsupported)
        provider.supportsFavorite = true
        for command: MediaCommand in [.play, .pause, .togglePlay, .next, .previous, .seek(12),
                                      .toggleShuffle, .toggleRepeat, .favorite(true), .refresh] {
            let result = await session.send(command)
            XCTAssertEqual(result, .submitted)
            XCTAssertEqual(provider.commands.last, command)
        }
    }

    @MainActor
    func testInFlightCommandDoesNotJumpProvidersAndReportsSuperseded() async {
        let a = ControlledProvider(), b = ControlledProvider(), session = MediaSession()
        a.onPlay = { session.select(b) }
        session.select(a)
        let result = await session.send(.play)
        XCTAssertEqual(result, .superseded)
        XCTAssertEqual(a.commands, [.play])
        XCTAssertTrue(b.commands.isEmpty)
    }

    @MainActor
    func testProviderReplacementAndShutdownOwnStopExactlyOnce() {
        let a = ControlledProvider(), b = ControlledProvider(), session = MediaSession()
        session.select(a)
        session.select(a)
        XCTAssertEqual(a.stopCount, 0, "Selecting the active instance is not replacement")
        session.select(b)
        XCTAssertEqual(a.stopCount, 1)
        XCTAssertEqual(b.stopCount, 0)
        session.stop(); session.stop()
        XCTAssertEqual(a.stopCount, 1)
        XCTAssertEqual(b.stopCount, 1)
        session.select(a)
        XCTAssertNil(session.provider)
    }

    func testEqualityIncludesVolumeRateAndTimestamp() {
        let original = PlaybackState(bundleIdentifier: "test")
        var changed = original
        changed.volume = 0.8
        XCTAssertNotEqual(changed, original)
        changed = original
        changed.playbackRate = 2
        XCTAssertNotEqual(changed, original)
        changed = original
        changed.lastUpdated = Date(timeIntervalSince1970: 0)
        XCTAssertNotEqual(changed, original)
    }
}
