//
//  PlaybackState.swift
//  anotchup
//
//  Created by Alexander on 2025-03-29.
//

import Foundation

public enum RepeatMode: Int, Codable, Sendable {
    case off = 1, one = 2, all = 3
}

public struct PlaybackState: Equatable, Sendable {
    public var bundleIdentifier: String
    public var isPlaying: Bool
    public var title: String
    public var artist: String
    public var album: String
    public var currentTime: Double
    public var duration: Double
    public var playbackRate: Double
    public var isShuffled: Bool
    public var repeatMode: RepeatMode
    public var lastUpdated: Date
    public var artwork: Data?
    public var volume: Double
    public var isFavorite: Bool

    public init(bundleIdentifier: String, isPlaying: Bool = false, title: String = "I'm Handsome",
                artist: String = "Me", album: String = "Self Love", currentTime: Double = 0,
                duration: Double = 0, playbackRate: Double = 1, isShuffled: Bool = false,
                repeatMode: RepeatMode = .off, lastUpdated: Date = .distantPast,
                artwork: Data? = nil, volume: Double = 0.5, isFavorite: Bool = false) {
        self.bundleIdentifier = bundleIdentifier
        self.isPlaying = isPlaying
        self.title = title
        self.artist = artist
        self.album = album
        self.currentTime = currentTime
        self.duration = duration
        self.playbackRate = playbackRate
        self.isShuffled = isShuffled
        self.repeatMode = repeatMode
        self.lastUpdated = lastUpdated
        self.artwork = artwork
        self.volume = volume
        self.isFavorite = isFavorite
    }
}

public enum MediaVisibilityPolicy {
    public static func hasCurrentTrack(title: String, lastUpdated: Date) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !title.isEmpty && title != "Unknown" && lastUpdated != .distantPast
    }
    public static func shouldShowPlayer(isPlaying: Bool, isIdle: Bool, keepWhilePaused: Bool, hasTrack: Bool) -> Bool {
        isPlaying || !isIdle || (keepWhilePaused && hasTrack)
    }
}
