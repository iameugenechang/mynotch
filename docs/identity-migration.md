# App identity migration

The app now uses `com.iameugenechang.anotchup`; its embedded helper and XPC client both use `com.iameugenechang.anotchup.AnotchupXPCHelper`. The remote repository is unchanged.

## Preferences

`AnotchupBootstrap.main()` runs migration before SwiftUI creates property wrappers, the app delegate, or services. `AppIdentity` owns merge policy; `AppIdentityAdapters.UserDefaultsDomain` reads and replaces persistent domains, not registered defaults or the combined search list.

The source is `com.iameugenechang.mynotch`. Every destination value wins over its source value, including false, empty collections, and opaque data. Missing keys copy unchanged. A completed marker prevents future launches from resurrecting keys that the user removed. A partial destination without the marker is merged with the same precedence. The source is never deleted or modified.

The adapter submits one domain replacement and synchronizes it; migration checks the read-back value. Failure prevents app construction rather than starting against an unverified domain. A retry can use retained source data. This is not a filesystem durability guarantee. UserDefaults cannot reliably distinguish a missing domain from an unreadable preference file. Feature-specific invalid payloads are preserved for the feature's existing recovery policy, not silently rewritten by migration. An invalid migration marker fails explicitly.

Tests share real isolated-domain and memory cases, covering precedence, opaque data, reconstruction, idempotence, fresh/partial domains, invalid markers/property lists, dropped writes, storage failures, and retry. They never open the actual source domain.

## Other identity state

- Shelf files use the separate staged directory copy described in [the rename contract](rename-contract.md). Bookmark bytes and referenced files remain unchanged. Corrupt JSON blocks Shelf writes until a successful reload; it is not partially decoded and overwritten.
- Temporary sharing files use an app-owned root. Legacy temporary files outside that root are not deleted.
- No app Keychain access was found. YouTube Music's client authorization path remains an external compatibility identifier; its token is held in memory. No saved external access is renamed.
- Login items belong to macOS and the installed app identity. The user may need to disable an old login item and enable the new app. Migration does not edit login-item registrations or uninstall the old app.
- Camera, Calendar/Reminders, Accessibility, and Automation grants may need approval again. No OS permission database is read or modified. Signing and sandbox rules can also affect bookmark access.
- Upstream updates stay disabled. Publishing workflows remain quarantined. This change neither publishes a release nor approves signing, dependency/asset licensing, or updater configuration.

The unsigned build verifies helper embedding and matching metadata. Live signed-helper resolution and permission prompts require a separate opt-in acceptance run.
