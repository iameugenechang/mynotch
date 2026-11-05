import AppKit
import AVFoundation
import Combine
import EventKit
import MediaFeature
import CameraFeature
import CalendarFeature
import UniformTypeIdentifiers

// Unused live defaults fail closed. Tests inject every transport and never construct
// an app singleton, execute AppleScript, discover devices, or contact a server.
enum AppleScriptHelper {
    static func executeVoid(_ text: String) async throws { fatalError("Unexpected AppleScript") }
    static func execute(_ text: String) async throws -> NSAppleEventDescriptor? { fatalError("Unexpected AppleScript") }
}
final class ImageService {
    static let shared = ImageService()
    func fetchImageData(from url: URL) async throws -> Data { fatalError("Unexpected network") }
}
@MainActor func makeAppWebcamManager() -> WebcamManager { fatalError("Unexpected composition") }
enum FixtureError: Error { case failed }

final class HTTPFixture: URLProtocol {
    static let lock = NSLock()
    private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.recorded.append(request); Self.lock.unlock()
        let path = request.url!.path
        let body: String
        switch path {
        case "/auth/boringNotch": body = #"{"accessToken":"fixture"}"#
        case "/api/v1/song": body = #"{"isPaused":false,"title":"Fixture","artist":"Artist","album":"Album","elapsedSeconds":12,"songDuration":120,"volume":40}"#
        case "/api/v1/like-state": body = #"{"likeStatus":"INDIFFERENT"}"#
        default: body = "{}"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: path.contains("failure") ? 500 : 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class CalendarFixture: CalendarBackend {
    var access: EKAuthorizationStatus = .fullAccess
    var values: [EventModel] = []
    var calls: [[String]] = []
    var failure = false
    let calendar = CalendarModel(id: "events", account: "Fixture", title: "Events", color: .blue, isSubscribed: false, isReminder: false)
    func status(for type: EKEntityType) -> EKAuthorizationStatus { access }
    func request(_ type: EKEntityType) async throws -> Bool { fatalError("Unexpected permission request") }
    func calendars(for type: EKEntityType) -> [CalendarModel] { type == .event ? [calendar] : [] }
    func events(from start: Date, to end: Date, ids: [String], type: EKEntityType) async throws -> [EventModel] {
        calls.append(ids)
        if failure { throw FixtureError.failed }
        return values
    }
    func complete(_ id: String, completed: Bool) throws { throw FixtureError.failed }
    func event(_ id: String, _ start: Date, _ end: Date) -> EventModel {
        EventModel(id: id, start: start, end: end, title: id, location: nil, notes: nil, url: nil, isAllDay: false, type: .event(.accepted), calendar: calendar, participants: [], timeZone: nil, hasRecurrenceRules: false, priority: nil)
    }
}

@main
struct NativeAdapterContractTests {
    @MainActor static var checks = 0
    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message); checks += 1
    }
    @MainActor static func wait(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Timed out waiting for controlled adapter")
    }
    @MainActor static func descriptor(spotify: Bool, title: String = "Fixture", art: String = "") -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        let fields: [NSAppleEventDescriptor] = [
            .init(boolean: true), .init(string: title), .init(string: "Artist"), .init(string: "Album"),
            .init(double: 12), .init(double: spotify ? 120_000 : 120), .init(boolean: false),
            spotify ? .init(boolean: false) : .init(int32: 1), .init(int32: 40), .init(string: art)
        ] + (spotify ? [] : [.init(boolean: true)])
        for (index, field) in fields.enumerated() { list.insert(field, at: index + 1) }
        return list
    }
    @MainActor static func main() async throws {
        try await media()
        try await camera()
        try await calendar()
        try await bookmarks()
        try await itemProviders()
        print("Native adapter contracts passed (\(checks) checks; no external services)")
    }
    @MainActor static func media() async throws {
        // The same observable/command/stop cases run on every production provider.
        var scripts: [String] = []
        var failFetch = false
        let apple = AppleMusicController(observe: false, execute: { scripts.append($0) }, fetch: { _ in
            if failFetch { throw FixtureError.failed }; return descriptor(spotify: false)
        }, running: { true })
        let spotify = SpotifyController(observe: false, execute: { scripts.append($0) }, fetch: { _ in
            if failFetch { throw FixtureError.failed }; return descriptor(spotify: true)
        }, running: { true }, loadArtwork: { _ in throw FixtureError.failed })
        var commands: [Int] = []
        let now = NowPlayingController(commands: .init(send: { command, _ in commands.append(command) }, seek: { _ in }, shuffle: { _ in }, repeatMode: { _ in }))
        let update = try JSONDecoder().decode(NowPlayingUpdate.self, from: Data(#"{"payload":{"bundleIdentifier":"fixture.player","title":"Fixture","artist":"Artist","album":"Album","duration":120,"elapsedTime":12,"playing":true,"volume":0.4}}"#.utf8))
        await now.handleAdapterUpdate(update)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPFixture.self]
        let network = URLSession(configuration: config)
        defer { network.invalidateAndCancel() }
        let http = YouTubeMusicHTTPClient(baseURL: "https://fixture.invalid", session: network)
        let youtube = YouTubeMusicController(observe: false, httpClient: http, running: { true }, loadArtwork: { _ in throw FixtureError.failed })
        for provider: any MediaProvider in [apple, spotify, now, youtube] {
            var latest: PlaybackState?
            let token = provider.playbackStatePublisher.sink { latest = $0 }
            await provider.updatePlaybackInfo()
            check(latest?.title == "Fixture", "Production playback mapping")
            check(latest?.duration == 120 && latest?.currentTime == 12, "Time unit mapping")
            check(latest?.volume == 0.4, "Normalized volume")
            let session = MediaSession()
            session.select(provider)
            let play = await session.send(.play)
            check(play == .submitted, "Common play submission contract")
            if !provider.supportsFavorite {
                let result = await session.send(.favorite(true))
                check(result == .unsupported, "Unsupported command is not transported")
            }
            token.cancel()
            // Do not stop until failure and generation cases below have run.
        }
        await apple.setFavorite(true)
        check(scripts.contains { $0.contains("set favorited of current track to true") }, "Favorite script interpolates Boolean")
        failFetch = true
        for provider: any MediaProvider in [apple, spotify] {
            var latest: PlaybackState?
            let token = provider.playbackStatePublisher.sink { latest = $0 }
            await provider.updatePlaybackInfo()
            check(latest?.title == "Fixture", "Failed refresh retains last valid snapshot")
            token.cancel()
        }
        do { _ = try await http.sendCommand(endpoint: "/failure", token: "fixture"); preconditionFailure("HTTP failure accepted") }
        catch { check(true, "HTTP failures propagate") }
        let before = (scripts.count, commands.count, HTTPFixture.requests.count)
        for provider: any MediaProvider in [apple, spotify, now, youtube] {
            provider.stop(); provider.stop()
            check(!provider.isActive(), "Stopped provider is unavailable")
            await provider.play(); await provider.updatePlaybackInfo()
        }
        check(scripts.count == before.0 && commands.count == before.1 && HTTPFixture.requests.count == before.2, "Stopped adapters reject future work")

        var replies: [CheckedContinuation<NSAppleEventDescriptor?, Error>] = []
        let delayed = AppleMusicController(observe: false, execute: { _ in }, fetch: { _ in
            try await withCheckedThrowingContinuation { replies.append($0) }
        }, running: { true })
        var result: PlaybackState?
        let token = delayed.playbackStatePublisher.sink { result = $0 }
        let old = Task { await delayed.updatePlaybackInfo() }
        await wait { replies.count == 1 }
        let fresh = Task { await delayed.updatePlaybackInfo() }
        await wait { replies.count == 2 }
        replies[1].resume(returning: descriptor(spotify: false, title: "New")); await fresh.value
        replies[0].resume(returning: descriptor(spotify: false, title: "Old")); await old.value
        check(result?.title == "New", "Late native playback cannot overwrite newer refresh")
        delayed.stop(); token.cancel()

        var imageReply: CheckedContinuation<Data, Error>?
        var track = "Old"
        let artwork = SpotifyController(observe: false, execute: { _ in }, fetch: { _ in
            descriptor(spotify: true, title: track, art: track == "Old" ? "https://fixture.invalid/art" : "")
        }, running: { true }, loadArtwork: { _ in try await withCheckedThrowingContinuation { imageReply = $0 } })
        let artToken = artwork.playbackStatePublisher.sink { result = $0 }
        await artwork.updatePlaybackInfo(); await wait { imageReply != nil }
        track = "New"; await artwork.updatePlaybackInfo()
        imageReply?.resume(returning: Data([1, 2]))
        for _ in 0..<10 { await Task.yield() }
        check(result?.title == "New" && result?.artwork == nil, "Late artwork cannot resurrect previous track")
        artwork.stop(); artToken.cancel()

        var youtubeReply: CheckedContinuation<Data, Error>?
        let delayedYouTube = YouTubeMusicController(observe: false, httpClient: http, running: { true }, loadArtwork: { _ in
            try await withCheckedThrowingContinuation { youtubeReply = $0 }
        })
        let youtubeToken = delayedYouTube.playbackStatePublisher.sink { result = $0 }
        await delayedYouTube.handleWebSocketMessage(Data(#"{"type":"PLAYER_INFO","song":{"title":"Old","imageSrc":"https://fixture.invalid/art"}}"#.utf8))
        await wait { youtubeReply != nil }
        await delayedYouTube.handleWebSocketMessage(Data(#"{"type":"PLAYER_INFO","song":{"title":"New"}}"#.utf8))
        youtubeReply?.resume(returning: Data([3, 4]))
        for _ in 0..<10 { await Task.yield() }
        check(result?.title == "New" && result?.artwork == nil, "YouTube late artwork cannot restore old track")
        delayedYouTube.stop()
        await delayedYouTube.handleWebSocketMessage(Data(#"{"type":"PLAYER_INFO","song":{"title":"Stopped"}}"#.utf8))
        check(result?.title == "New", "Stopped YouTube adapter rejects queued socket data")
        youtubeToken.cancel()
    }
    @MainActor static func camera() async throws {
        var auth: CameraAuthorization = .denied
        var available = true
        var starts = 0, stops = 0, prompts = 0
        let device = AVCameraDevice(effects: .init(authorization: { auth }, available: { available }, request: { prompts += 1; auth = .allowed }, start: { starts += 1; return nil }, stop: { stops += 1 }))
        do { try await device.start(); preconditionFailure("Denied camera started") } catch {}
        check(starts == 0 && prompts == 0, "Start never requests camera permission")
        auth = .unknown
        let granted = await device.requestAuthorization()
        check(granted == .allowed && prompts == 1, "Explicit camera request maps updated status")
        _ = await device.requestAuthorization()
        check(prompts == 1, "Known status never reprompts")
        available = false
        do { try await device.start(); preconditionFailure("Missing camera started") } catch {}
        check(starts == 0, "Unavailable hardware never acquired")
        available = true
        let session = CameraSession(device: device)
        session.start(); await wait { starts == 1 }
        session.shutdown(); await wait { stops == 1 }
        check(device.previewLayer == nil, "Shutdown releases preview")
    }
    @MainActor static func calendar() async throws {
        let backend = CalendarFixture()
        let service = CalendarService(backend: backend)
        let start = Date(timeIntervalSince1970: 100), end = start.addingTimeInterval(100)
        backend.values = [backend.event("inside", start, end), backend.event("next", end, end), backend.event("before", start.addingTimeInterval(-10), start)]
        let values = try await service.events(from: start, to: end, calendars: ["events"])
        check(values.map(\.id) == ["inside"], "Native calendar half-open filtering")
        check(backend.calls == [["events"]], "No empty reminders query widens to all calendars")
        let empty = try await service.events(from: start, to: end, calendars: [])
        check(empty.isEmpty && backend.calls.count == 1, "Empty selection does not query backend")
        backend.access = .denied
        do { _ = try await service.events(from: start, to: end, calendars: ["events"]); preconditionFailure("Denied calendar read") } catch {}
        do { try await service.setReminderCompleted(reminderID: "x", completed: true); preconditionFailure("Denied mutation") } catch {}
        check(backend.calls.count == 1, "Denied queries cannot contact backend")
        backend.access = .fullAccess; backend.failure = true
        do { _ = try await service.events(from: start, to: end, calendars: ["events"]); preconditionFailure("Failure became empty success") } catch { check(true, "Calendar failures propagate") }
    }
    @MainActor static func itemProviders() async throws {
        let text = NSItemProvider(item: "fixture" as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
        let value = await text.extractText()
        check(value == "fixture", "Production provider decodes text")
        let raw = NSItemProvider(item: Data([1, 2, 3]) as NSData, typeIdentifier: UTType.data.identifier)
        let bytes = await raw.loadData()
        check(bytes == Data([1, 2, 3]), "Production provider preserves bytes")
        let failed = NSItemProvider()
        failed.registerItem(forTypeIdentifier: UTType.utf8PlainText.identifier) { completion, _, _ in completion?(nil, FixtureError.failed) }
        let missing = await failed.extractText()
        check(missing == nil, "Failed provider returns no text")
        let invalidFile = NSItemProvider(item: "https://fixture.invalid/file" as NSString, typeIdentifier: UTType.fileURL.identifier)
        let invalidURL = await invalidFile.extractFileURL()
        check(invalidURL == nil, "File provider cannot return a remote URL")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("com.apple.SwiftUI.filePromises-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.txt")
        try Data("kept".utf8).write(to: file)
        let promise = NSItemProvider(item: file as NSURL, typeIdentifier: UTType.data.identifier)
        let copied = await promise.loadData()
        check(copied == Data("kept".utf8), "Promise bytes are copied")
        check(FileManager.default.fileExists(atPath: file.path), "Provider-owned file survives import")
        let path = NSItemProvider(item: file.path as NSString, typeIdentifier: UTType.fileURL.identifier)
        let decoded = await path.extractFileURL()
        check(decoded?.isFileURL == true && decoded?.path == file.path, "Plain file paths become file URLs")
    }

    @MainActor static func bookmarks() async throws {
        check(Bookmark(data: Data()).resolveURL() == nil, "Empty bookmark rejected")
        check(Bookmark(data: Data([0, 1, 2])).resolveURL() == nil, "Corrupt bookmark rejected")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.txt")
        try Data("fixture".utf8).write(to: file)
        let bookmark = try Bookmark(url: file)
        check(bookmark.resolveURL()?.standardizedFileURL.path == file.standardizedFileURL.path, "Real bookmark round trip")
        try FileManager.default.removeItem(at: file)
        let valid = await bookmark.validate()
        check(!valid, "Deleted bookmarked file is unavailable")
    }
}
