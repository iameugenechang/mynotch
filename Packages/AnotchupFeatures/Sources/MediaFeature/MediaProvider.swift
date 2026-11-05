//
//  MediaControllerProtocol.swift
//  anotchup
//
//  Created by Alexander on 2025-03-29.
//

import Combine
import Foundation

/// Legacy player transports publish snapshots from any queue. MediaSession
/// delivers them on the main actor and rejects callbacks from replaced providers.
/// Void commands report submission, not confirmed player success.
public protocol MediaProvider: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var supportsVolumeControl: Bool { get }
    var supportsFavorite: Bool { get }
    func setFavorite(_ favorite: Bool) async
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func setVolume(_ level: Double) async
    func isActive() -> Bool
    func updatePlaybackInfo() async
    func refresh() async
}

public extension MediaProvider {
    func refresh() async { await updatePlaybackInfo() }
}

public enum MediaCommand: Equatable, Sendable {
    case play, pause, togglePlay, next, previous, toggleShuffle, toggleRepeat, refresh
    case seek(Double), volume(Double), favorite(Bool)
}
public enum MediaCommandResult: Equatable, Sendable {
    case submitted, unsupported, unavailable, invalidArgument, superseded
}
