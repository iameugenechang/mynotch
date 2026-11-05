# Media contract

`MediaFeature` owns normalized playback snapshots, provider selection, command routing, capabilities, and revision checks. `MusicManager` remains the native presentation facade. App composition constructs providers and supplies playback-preview effects. The feature has no shell, AppKit, or player-service dependency.

Provider streams may publish from any queue. The session delivers state on the main actor. Replacement unsubscribes and stops the previous provider and rejects its queued publications. Selecting the same instance is a no-op. Stop is terminal and stops the current provider once. Playback position, rate, and volume participate in snapshot equality; only provider/content changes invalidate artwork and lyrics revisions.

Commands capture their provider. Replacement during an await reports `superseded`; it never redirects a command to a replacement player. Invalid numeric arguments and unsupported capabilities do not reach the provider. Volume is clamped to 0...1. `submitted` means the legacy adapter returned, not that an external player succeeded: native adapters still swallow some transport errors.

The native manager cancels lyric work on replacement and checks revisions before applying lyric, artwork, or color results. Startup and teardown own their subscriptions/tasks. Preference declarations no longer construct the media singleton; composition resolves the deprecated Now Playing fallback.

Six package tests cover provider replacement, queued delivery, content revisions, stop ownership, teardown, command routing, input/capability checks, and equality. `scripts/test-native-contracts.sh` additionally compiles all four production providers and runs common snapshot, time-unit, volume, command, capability, and stop cases. Controlled AppleScript responses, MediaRemote commands/data, and URLProtocol HTTP responses avoid external services. Native refresh/artwork tests deliver old results after replacement; HTTP failure remains distinguishable at the transport layer.

Provider stop invalidates refresh/artwork/socket generations and cancels owned startup, observer, polling, and reconnect work. The YouTube HTTP/auth/socket paths reject replaced generations. These checks do not prove that a live third-party protocol, lyrics endpoint, or private MediaRemote framework works. Live player/automation acceptance remains opt-in.
