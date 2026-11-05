# Media contract

`MediaFeature` owns normalized playback snapshots, provider selection, command routing, capabilities, and revision checks. `MusicManager` remains the native presentation facade. App composition constructs providers and supplies playback-preview effects. The feature has no shell, AppKit, or player-service dependency.

Provider streams may publish from any queue. The session delivers state on the main actor. Replacement unsubscribes the previous provider and rejects its queued publications. Stop is terminal. Playback position, rate, and volume participate in snapshot equality; only provider/content changes invalidate artwork and lyrics revisions.

Commands capture their provider. Replacement during an await reports `superseded`; it never redirects a command to a replacement player. Invalid numeric arguments and unsupported capabilities do not reach the provider. Volume is clamped to 0...1. `submitted` means the legacy adapter returned, not that an external player succeeded: native adapters still swallow some transport errors.

The native manager cancels lyric work on replacement and checks revisions before applying lyric, artwork, or color results. Startup and teardown own their subscriptions/tasks. Preference declarations no longer construct the media singleton; composition resolves the deprecated Now Playing fallback.

Five package tests cover provider replacement, queued delivery, content revisions, teardown, command routing, input/capability checks, and equality. They use a controlled provider, not the production AppleScript, XPC, or YouTube adapters. Controlled-transport adapter conformance and native player acceptance remain outstanding. The unsigned app build passes without launching players or requesting automation permission.
