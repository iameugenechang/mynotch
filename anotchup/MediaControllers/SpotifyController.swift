//
//  SpotifyController.swift
//  anotchup
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class SpotifyController: @preconcurrency MediaControllerProtocol {
    func setFavorite(_ favorite: Bool) async {
        //Placeholder
    }
    
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.spotify.client"
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { false }

    private var notificationTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    
    // Constant for time between command and update
    private let commandUpdateDelay: Duration = .milliseconds(25)

    private var lastArtworkURL: String?
    private var artworkFetchTask: Task<Void, Never>?
    
    private let execute: (String) async throws -> Void
    private let fetch: (String) async throws -> NSAppleEventDescriptor?
    private let running: () -> Bool
    private let loadArtwork: (URL) async throws -> Data
    private var refreshRevision = UUID()
    private var stopped = false

    func stop() {
        stopped = true
        refreshRevision = UUID()
        startupTask?.cancel()
        notificationTask?.cancel()
        notificationTask = nil
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
    }

    init(observe: Bool = true,
         execute: @escaping (String) async throws -> Void = AppleScriptHelper.executeVoid,
         fetch: @escaping (String) async throws -> NSAppleEventDescriptor? = AppleScriptHelper.execute,
         running: @escaping () -> Bool = { NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" } },
         loadArtwork: @escaping (URL) async throws -> Data = { try await ImageService.shared.fetchImageData(from: $0) }) {
        self.execute = execute
        self.fetch = fetch
        self.running = running
        self.loadArtwork = loadArtwork
        guard observe else { return }
        setupPlaybackStateChangeObserver()
        startupTask = Task { [weak self] in
            guard let self, self.isActive() else { return }
            await self.updatePlaybackInfo()
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )
            
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        startupTask?.cancel()
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async { await executeCommand("play") }
    func pause() async { await executeCommand("pause") }
    func togglePlay() async { await executeCommand("playpause") }
    func nextTrack() async { await executeCommand("next track") }
    func previousTrack() async {
        await executeAndRefresh("previous track")
    }
    
    func seek(to time: Double) async {
        await executeAndRefresh("set player position to \(time)")
    }
    
    func toggleShuffle() async {
        await executeAndRefresh("set shuffling to not shuffling")
    }
    
    func toggleRepeat() async {
        await executeAndRefresh("set repeating to not repeating")
    }
    
    func setVolume(_ level: Double) async {
        guard !stopped, level.isFinite else { return }
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        !stopped && running()
    }
    
    func updatePlaybackInfo() async {
        guard !stopped else { return }
        let revision = UUID()
        refreshRevision = revision
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        guard let descriptor = try? await fetchPlaybackInfoAsync(),
              !Task.isCancelled, refreshRevision == revision, descriptor.numberOfItems >= 10 else { return }
        
        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0)/1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        let artworkURL = descriptor.atIndex(10)?.stringValue ?? ""
        
        var state = PlaybackState(
            bundleIdentifier: "com.spotify.client",
            isPlaying: isPlaying,
            title: currentTrack,
            artist: currentTrackArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            isShuffled: isShuffled,
            repeatMode: isRepeating ? .all : .off,
            lastUpdated: Date(),
            artwork: nil,
            volume: Double(volumePercentage) / 100.0
        )

        if artworkURL == lastArtworkURL, let existingArtwork = self.playbackState.artwork {
            state.artwork = existingArtwork
        }

        playbackState = state

        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            guard artworkURL != lastArtworkURL || state.artwork == nil else { return }
            artworkFetchTask?.cancel()

            let loadArtwork = self.loadArtwork
            artworkFetchTask = Task { [weak self] in
                do {
                    let data = try await loadArtwork(url)
                    guard !Task.isCancelled else { return }

                    await MainActor.run { [weak self] in
                        guard let self, self.refreshRevision == revision else { return }
                        var updatedState = self.playbackState
                        updatedState.artwork = data
                        self.playbackState = updatedState
                        self.lastArtworkURL = artworkURL
                        self.artworkFetchTask = nil
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        guard self?.refreshRevision == revision else { return }
                        self?.artworkFetchTask = nil
                    }
                }
            }
        }
    }
    
// MARK: - Private Methods
    
    private func executeCommand(_ command: String) async {
        guard !stopped else { return }
        let script = "tell application \"Spotify\" to \(command)"
        try? await execute(script)
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Spotify"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffling
                set repeatState to repeating
                set currentVolume to sound volume
                set artworkURL to artwork url of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, currentVolume, artworkURL}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, 50, ""}
            end try
        end tell
        """
        
        return try await fetch(script)
    }
    
}
