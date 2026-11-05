import Combine
import Foundation

@MainActor
public final class MediaSession: ObservableObject {
    public struct Revision: Equatable, Sendable { fileprivate let value: UUID }
    @Published public private(set) var state: PlaybackState?
    public private(set) var provider: (any MediaProvider)?
    public private(set) var revision = Revision(value: UUID())
    private var generation = UUID()
    private var subscription: AnyCancellable?
    private var stopped = false

    public init() {}

    public func select(_ provider: (any MediaProvider)?) {
        guard !stopped else { return }
        if let current = self.provider, let provider, current === provider { return }
        self.provider?.stop()
        generation = UUID()
        revision = Revision(value: UUID())
        subscription = nil
        self.provider = provider
        state = nil
        let selectedGeneration = generation
        subscription = provider?.playbackStatePublisher.sink { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self, !self.stopped, self.generation == selectedGeneration else { return }
                if self.state?.bundleIdentifier != snapshot.bundleIdentifier || self.state?.title != snapshot.title
                    || self.state?.artist != snapshot.artist || self.state?.album != snapshot.album
                    || self.state?.artwork != snapshot.artwork {
                    self.revision = Revision(value: UUID())
                }
                self.state = snapshot
            }
        }
    }

    public func isCurrent(_ revision: Revision) -> Bool { !stopped && self.revision == revision }

    public func stop() {
        guard !stopped else { return }
        provider?.stop()
        stopped = true
        generation = UUID()
        revision = Revision(value: UUID())
        subscription = nil
        provider = nil
        state = nil
    }

    /// Captures the provider before suspension. A replacement never redirects an
    /// in-flight command to another player. Superseded does not undo external effects.
    public func send(_ command: MediaCommand) async -> MediaCommandResult {
        guard !stopped, let provider else { return .unavailable }
        let selectedGeneration = generation
        switch command {
        case .volume(let value):
            guard provider.supportsVolumeControl else { return .unsupported }
            guard value.isFinite else { return .invalidArgument }
            await provider.setVolume(min(1, max(0, value)))
        case .favorite(let value):
            guard provider.supportsFavorite else { return .unsupported }
            await provider.setFavorite(value)
        case .seek(let value):
            guard value.isFinite && value >= 0 else { return .invalidArgument }
            await provider.seek(to: value)
        case .play: await provider.play()
        case .pause: await provider.pause()
        case .togglePlay: await provider.togglePlay()
        case .next: await provider.nextTrack()
        case .previous: await provider.previousTrack()
        case .toggleShuffle: await provider.toggleShuffle()
        case .toggleRepeat: await provider.toggleRepeat()
        case .refresh: await provider.refresh()
        }
        return !stopped && generation == selectedGeneration ? .submitted : .superseded
    }
}
