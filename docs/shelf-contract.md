# Shelf contract

`ShelfFeature` owns collection changes, async import/validation policy, and sharing completion. `ShelfAdapters` provides atomic JSON snapshot storage. Native bookmarks, item-provider decoding, icons, pasteboard, security scopes, and sharing UI stay in the app.

## Persistence and collection

- Production and memory persistence run the same collection scenarios. Missing files mean an empty shelf; malformed snapshots and I/O failures throw. Failed loads block writes until a successful explicit reload, preserving the original bytes rather than overwriting corruption.
- Commits save before publishing changes or deleting removed resources. Failed saves retain the previous collection and expose an error. Atomic replacement is not a crash-durability guarantee.
- Deduplication preserves existing item order. Async validation removes only unchanged invalid items, so concurrent drops and bookmark refreshes survive.
- Concurrent imports keep loading active until all return. Stop rejects new work; late imports clean only resources not retained by the collection. Native item-provider operations may finish after stop.
- The existing JSON shape and `anotchup/Shelf` location remain unchanged. Legacy storage migration is covered separately in `rename-contract.md`.

## Temporary files and sharing

Item-provider promise files remain provider-owned: import copies bytes and never deletes the original file or directory. File-URL decoding rejects remote URLs and turns absolute paths into file URLs.

New temporary files live under `anotchup-shelf` in the system temporary directory. Suggested filenames are reduced to a leaf name. Cleanup rejects unrelated paths, sibling-prefix paths, and symlinks resolving outside that root. Legacy temporary files elsewhere are deliberately not deleted automatically.

Each `ShareInteraction` acquires one close-protection count. Picker-to-service handoff does not increment it twice. Success, failure, picker cancellation, and explicit shutdown release it and run cleanup once. A canceled picker callback cannot finish an already-running service. There is no two-second timeout pretending a share has completed.

Quick sharing retains each operation's security-scoped access and temporary text files until its completion callback. Concurrent operations do not revoke each other's access. A missing presentation view cancels instead of leaking protection. A native service that never reports completion retains resources until explicit shutdown; physical system sharing behavior still needs manual acceptance.

## Verification limits

Package tests cover collection behavior with real JSON and memory persistence, failed writes, corruption recovery, concurrent validation, canceled imports, and sharing callback policy. Standalone tests exercise production temporary-file creation/deletion, real bookmark round trips/corruption/missing files, and in-process item-provider data/text/error/file/promise cases. All files are temporary fixtures. Tests do not open a picker, access user bookmarks, request user security scopes, or invoke a sharing service. OS sharing callbacks and sandbox access remain manual acceptance.
