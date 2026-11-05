//
//  YouTubeMusicController.swift
//  anotchup
//
//  Created By Alexander on 2025-03-30.
//  Modified by Pranav on 2025-06-16.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class YouTubeMusicController: @preconcurrency MediaControllerProtocol {
    // MARK: - Published Properties
    @Published var playbackState = PlaybackState(
        bundleIdentifier: YouTubeMusicConfiguration.default.bundleIdentifier
    )

    private var artworkFetchTask: Task<Void, Never>?
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { true }

    func setFavorite(_ favorite: Bool) async {
        guard !stopped else { return }
        let current = revision
        do {
            let token = try await authManager.authenticate()
            guard !stopped, current == revision, !Task.isCancelled else { return }
            if favorite && !playbackState.isFavorite {
                _ = try await httpClient.toggleLike(token: token)
            } else if !favorite && playbackState.isFavorite {
                _ = try await httpClient.toggleLike(token: token)
            }
            try? await Task.sleep(for: .milliseconds(150))
            await updatePlaybackInfo()
        } catch {
            print("[YouTubeMusicController] Failed to set favorite: \(error)")
        }
    }

    // MARK: - Private Properties
    private let configuration: YouTubeMusicConfiguration
    private let httpClient: YouTubeMusicHTTPClient
    private let authManager: YouTubeMusicAuthManager
    private var webSocketClient: YouTubeMusicWebSocketClient?
    
    private var updateTimer: Timer?
    private var appStateObserver: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1.0
    private var stopped = false
    private var revision = UUID()
    private var artworkRevision = UUID()
    private var connectionRevision = UUID()
    private var startupTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private let running: () -> Bool
    private let loadArtwork: (URL) async throws -> Data

    func stop() {
        guard !stopped else { return }
        stopped = true
        connectionRevision = UUID()
        revision = UUID()
        artworkRevision = UUID()
        startupTask?.cancel()
        reconnectTask?.cancel()
        appStateObserver?.cancel()
        artworkFetchTask?.cancel()
        stopPeriodicUpdates()
        let client = webSocketClient
        webSocketClient = nil
        let auth = authManager
        Task { await client?.disconnect(); await auth.invalidateToken() }
    }

    deinit {
        startupTask?.cancel()
        reconnectTask?.cancel()
        appStateObserver?.cancel()
        artworkFetchTask?.cancel()
        updateTimer?.invalidate()
        let client = webSocketClient
        Task { await client?.disconnect() }
    }
    
    // MARK: - Initialization
    init(configuration: YouTubeMusicConfiguration = .default, observe: Bool = true,
         httpClient: YouTubeMusicHTTPClient? = nil, running: (() -> Bool)? = nil,
         loadArtwork: @escaping (URL) async throws -> Data = { try await ImageService.shared.fetchImageData(from: $0) }) {
        self.configuration = configuration
        self.httpClient = httpClient ?? YouTubeMusicHTTPClient(baseURL: configuration.baseURL)
        self.authManager = YouTubeMusicAuthManager(httpClient: self.httpClient)
        self.running = running ?? { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == configuration.bundleIdentifier } }
        self.loadArtwork = loadArtwork
        guard observe else { return }
        setupAppStateObserver()
        startupTask = Task { [weak self] in await self?.initializeIfAppActive() }
    }
    
    // MARK: - MediaControllerProtocol Implementation
    func play() async { await sendCommand(endpoint: "/play", method: "POST") }
    
    func pause() async { await sendCommand(endpoint: "/pause", method: "POST") }
    
    func togglePlay() async {
        if !isActive() { launchApp() }
        await sendCommand(endpoint: "/toggle-play", method: "POST")
    }
    
    func nextTrack() async { await sendCommand(endpoint: "/next", method: "POST") }

    func previousTrack() async { await sendCommand(endpoint: "/previous", method: "POST") }
    
    func seek(to time: Double) async {
        let payload = ["seconds": time]
        await sendCommand(endpoint: "/seek-to", method: "POST", body: payload)
    }

    func setVolume(_ level: Double) async {
        guard level.isFinite, !stopped else { return }
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        let payload = ["volume": volumePercentage]
        await sendCommand(endpoint: "/volume", method: "POST", body: payload)
    }
    func fetchShuffleState() async { await sendCommand(endpoint: "/shuffle", method: "GET", refresh: false) }
    func fetchRepeatMode() async { await sendCommand(endpoint: "/repeat-mode", method: "GET", refresh: false) }
    
    func toggleShuffle() async { await sendCommand(endpoint: "/shuffle", method: "POST") }
    func toggleRepeat() async { await sendCommand(endpoint: "/switch-repeat", method: "POST") }

    func isActive() -> Bool { !stopped && running() }
    
    func updatePlaybackInfo() async {
        guard !stopped else { return }
        let current = UUID()
        revision = current
        guard isActive() else {
            resetPlaybackState()
            return
        }
        
        do {
            let token = try await authManager.authenticate()
            guard !stopped, revision == current, !Task.isCancelled else { return }
            let response = try await httpClient.getPlaybackInfo(token: token)
            guard !stopped, revision == current, !Task.isCancelled else { return }
            updatePlaybackState(with: response)
            // Fetch like state if supported
            do {
                let likeResp = try await httpClient.getLikeState(token: token)
                guard !stopped, revision == current, !Task.isCancelled else { return }
                var newState = playbackState
                    if let state = likeResp.state {
                        switch state.uppercased() {
                        case "LIKE":
                            newState.isFavorite = true
                        case "DISLIKE":
                            // We don't have a separate dislike UI yet, treat as not favorited
                            newState.isFavorite = false
                        default:
                            newState.isFavorite = false
                        }
                    } else {
                        newState.isFavorite = false
                    }
                playbackState = newState
            } catch {
                // Don't treat it as an error if the like endpoint doesn't exist — just skip
            }
        } catch YouTubeMusicError.authenticationRequired {
            guard !stopped, revision == current else { return }
            await authManager.invalidateToken()
        } catch {
            print("[YouTubeMusicController] Failed to update playback info: \(error)")
        }
    }
    
    // MARK: - Private Methods
    private func setupAppStateObserver() {
        appStateObserver = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let launchNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didLaunchApplicationNotification
                    )
                    
                    for await notification in launchNotifications {
                        await self?.handleAppLaunched(notification)
                    }
                }
                
                group.addTask {
                    let terminateNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didTerminateApplicationNotification
                    )
                    
                    for await notification in terminateNotifications {
                        await self?.handleAppTerminated(notification)
                    }
                }
            }
        }
    }
    
    private func handleAppLaunched(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == configuration.bundleIdentifier else {
            return
        }
        
        await initializeIfAppActive()
    }
    
    private func handleAppTerminated(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == configuration.bundleIdentifier else {
            return
        }
        
        guard !stopped else { return }
        stopPeriodicUpdates()
        reconnectTask?.cancel()
        connectionRevision = UUID()
        let client = webSocketClient
        webSocketClient = nil
        resetPlaybackState()
        await client?.disconnect()
    }
    
    private func initializeIfAppActive() async {
        guard isActive(), !Task.isCancelled else { return }
        do {
            let token = try await authManager.authenticate()
            guard isActive(), !Task.isCancelled else { return }
            await setupWebSocketIfPossible(token: token)
            await startPeriodicUpdates()
            await updatePlaybackInfo()
        } catch {
            print("[YouTubeMusicController] Failed to initialize: \(error)")
            await scheduleReconnect()
        }
    }
    
    private func setupWebSocketIfPossible(token: String) async {
        guard !stopped else { return }
        let generation = UUID()
        connectionRevision = generation
        guard let wsURL = WebSocketURLBuilder.buildURL(from: configuration.baseURL) else {
            print("[YouTubeMusicController] Failed to build WebSocket URL")
            return
        }
        
        let client = YouTubeMusicWebSocketClient(
            onMessage: { [weak self] data in
                guard let self else { return }
                await self.deliverWebSocketMessage(data, generation: generation)
            },
            onDisconnect: { [weak self] in
                guard let self else { return }
                await self.handleWebSocketDisconnect(generation: generation)
            }
        )
        
        do {
            try await client.connect(to: wsURL, with: token)
            guard !stopped, connectionRevision == generation, !Task.isCancelled else { await client.disconnect(); return }
            let previous = webSocketClient
            webSocketClient = client
            await previous?.disconnect()
            guard !stopped, connectionRevision == generation else { return }
            stopPeriodicUpdates() // WebSocket will provide real-time updates
            reconnectDelay = configuration.reconnectDelay.lowerBound
        } catch {
            print("[YouTubeMusicController] WebSocket connection failed: \(error)")
            await scheduleReconnect()
        }
    }
    
    private func deliverWebSocketMessage(_ data: Data, generation: UUID) async {
        guard connectionRevision == generation else { return }
        await handleWebSocketMessage(data)
    }

    func handleWebSocketMessage(_ data: Data) async {
        guard !stopped else { return }
        revision = UUID()
        guard let message = WebSocketMessage(from: data) else {
            if let response = try? JSONDecoder().decode(PlaybackResponse.self, from: data) {
                updatePlaybackState(with: response)
            }
            return
        }
        switch message.type {
        case .playerInfo, .videoChanged, .playerStateChanged:
            if let data = message.extractData(),
               let response = PlaybackResponse.from(websocketData: data) {
                updatePlaybackState(with: response)
            }

        case .positionChanged:
            guard let data = message.extractData() else { return }

            var position: Double? = nil
            if let pos = data["position"] as? Double {
                position = pos
            } else if let elapsed = data["elapsedSeconds"] as? Double {
                position = elapsed
            }
            guard let newPosition = position else { return }

            var copied = playbackState
            copied.currentTime = newPosition
            copied.lastUpdated = Date()
            if copied != playbackState { playbackState = copied }

        case .repeatChanged:
            guard let data = message.extractData() else { return }
            var copy = playbackState

            if let repeatStr = data["repeat"] as? String {
                switch repeatStr.uppercased() {
                case "NONE": copy.repeatMode = .off
                case "ALL": copy.repeatMode = .all
                case "ONE": copy.repeatMode = .one
                default: break
                }
            }
            copy.lastUpdated = Date()
            if copy != playbackState { playbackState = copy }

        case .shuffleChanged:
            guard let data = message.extractData() else { return }
            var copy = playbackState
            if let shuffle = data["shuffle"] as? Bool { copy.isShuffled = shuffle }
            else if let shuffle = data["isShuffled"] as? Bool { copy.isShuffled = shuffle }
            copy.lastUpdated = Date()
            if copy != playbackState { playbackState = copy }

        case .volumeChanged:
            guard let data = message.extractData() else { return }
            var copy = playbackState
            if let volume = data["volume"] as? Double {
                copy.volume = volume / 100.0
            } else if let volume = data["volume"] as? Int {
                copy.volume = Double(volume) / 100.0
            }
            copy.lastUpdated = Date()
            if copy != playbackState { playbackState = copy }
        }
    }
    
    private func handleWebSocketDisconnect(generation: UUID) async {
        guard !stopped, connectionRevision == generation else { return }
        connectionRevision = UUID()
        webSocketClient = nil
        await startPeriodicUpdates() // Fallback to polling
        await scheduleReconnect()
    }
    
    private func scheduleReconnect() async {
        guard !stopped else { return }
        reconnectTask?.cancel()
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, configuration.reconnectDelay.upperBound)
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, !self.stopped, self.isActive(), !Task.isCancelled else { return }
            await self.initializeIfAppActive()
        }
    }
    
    private func startPeriodicUpdates() async {
        guard isActive() && webSocketClient == nil else { return }
        
        stopPeriodicUpdates()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: configuration.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func refresh() async { await pollPlaybackState() }

    func pollPlaybackState() async {
        if !isActive() {
            return
        }
        
        await fetchRepeatMode()
        await fetchShuffleState()
        await updatePlaybackInfo()
    }
    
    private func sendCommand(
        endpoint: String,
        method: String = "POST",
        body: (any Codable & Sendable)? = nil,
        refresh: Bool = true
    ) async {
        guard !stopped, !Task.isCancelled else { return }
        let current = revision
        do {
            let token = try await authManager.authenticate()
            guard !stopped, !Task.isCancelled else { return }
            
            let data = try await httpClient.sendCommand(
                endpoint: endpoint,
                method: method,
                body: body,
                token: token
            )
            guard !stopped, revision == current, !Task.isCancelled else { return }
            // Lightweight endpoint-specific parsing
            if endpoint == "/shuffle" {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let shuffleState = json["state"] as? Bool {
                    playbackState.isShuffled = shuffleState
                } else {
                    playbackState.isShuffled = !playbackState.isShuffled
                }
            } else if endpoint == "/repeat-mode" {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let mode = json["mode"] as? String { updateRepeatMode(mode) }
                }
            }  else if endpoint == "/switch-repeat" {
                // Find next repeat mode
                let nextMode: RepeatMode
                switch playbackState.repeatMode {
                case .off: nextMode = .all
                case .all: nextMode = .one
                case .one: nextMode = .off
                }
                playbackState.repeatMode = nextMode
            } else if refresh && webSocketClient == nil {
                try? await Task.sleep(for: .milliseconds(100))
                await updatePlaybackInfo()
            }
        } catch YouTubeMusicError.authenticationRequired {
            await authManager.invalidateToken()
        } catch {
            print("[YouTubeMusicController] Command failed: \(error)")
        }
    }
    
    private func updatePlaybackState(with response: PlaybackResponse) {
        guard !stopped else { return }
        let current = UUID()
        artworkRevision = current
        var newState = playbackState
        
        newState.isPlaying = !response.isPaused

        if let title = response.title {
            newState.title = title
        }

        if let artist = response.artist {
            newState.artist = artist
        }

        if let album = response.album {
            newState.album = album
        }

        if let elapsed = response.elapsedSeconds {
            newState.currentTime = elapsed
        }

        if let duration = response.songDuration {
            newState.duration = duration
        }

        newState.lastUpdated = Date()
        
        if let shuffled = response.isShuffled {
            newState.isShuffled = shuffled
        }
        
        if let mode = response.repeatMode {
            switch mode {
            case 0: newState.repeatMode = .off
            case 1: newState.repeatMode = .all
            case 2: newState.repeatMode = .one
            default: break
            }
        }

        if let volume = response.volume {
            newState.volume = volume / 100.0
        }

        if newState != playbackState {
            if newState.title != playbackState.title || newState.artist != playbackState.artist || newState.album != playbackState.album {
                newState.artwork = nil
                newState.isFavorite = false
            }
            playbackState = newState

            artworkFetchTask?.cancel()
            artworkFetchTask = nil

            if let artworkURL = response.imageSrc,
               let url = URL(string: artworkURL) {
                let loadArtwork = self.loadArtwork
                artworkFetchTask = Task { [weak self] in
                    do {
                        let data = try await loadArtwork(url)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { [weak self] in
                            guard let self, !self.stopped, self.artworkRevision == current else { return }
                            self.playbackState.artwork = data

                        }
                    } catch { /* ignore */ }
                }
            }
        }
    }
    
    private func resetPlaybackState() {
        revision = UUID()
        artworkRevision = UUID()
        artworkFetchTask?.cancel()
        playbackState = PlaybackState(
            bundleIdentifier: configuration.bundleIdentifier,
            isPlaying: false
        )
    }
    
    private func launchApp() {
        guard !stopped else { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: configuration.bundleIdentifier) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

     private func updateRepeatMode(_ mode: String) {
        var target: RepeatMode? = nil
        switch mode {
            case "NONE": target = .off
            case "ALL": target = .all
            case "ONE": target = .one
            default: break
        }
        if let target, target != playbackState.repeatMode { playbackState.repeatMode = target }
    }
    
}
