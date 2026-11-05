# anotchup rename contract

## Product and build identity

The Xcode project, scheme, source directory, and app product are `anotchup`. App-owned branded types use `Anotchup`; extracted components keep responsibility names such as `OneGoalStore` and `NotchDelayedActionSession`. The helper target, product, and protocol use `AnotchupXPCHelper`.

The main bundle identifier is `com.iameugenechang.anotchup`. The embedded helper and client service name both use `com.iameugenechang.anotchup.AnotchupXPCHelper`. Preferences migrate before app construction from the retained legacy domain. See [app identity migration](identity-migration.md) for precedence, failures, and OS-managed permissions. Static checks and the unsigned build verify matching identifiers and embedding, not a live signed XPC connection or retained permission grants.

Working on keys, Codable fields, appearance preferences, and other non-branded settings do not change. The repository remains `https://github.com/iameugenechang/mynotch`.

## Shelf storage

`ShelfStorageLocation.prepare(in:)` selects Application Support storage:

1. If `anotchup/Shelf` exists, use it, including an intentionally empty shelf. Never overwrite it from legacy data.
2. Otherwise, if `boringNotch/Shelf` exists, copy its contents into a temporary sibling directory, then move the complete copy to the new location.
3. If neither exists, create the new directory.

The migration does not decode or rewrite `items.json`, bookmarks, or file references. It does not delete the old directory. A thrown copy failure cleans its staging directory and leaves the destination absent. The persistence service falls back to the old directory when available and retries migration on the next launch. Malformed Shelf JSON fails explicitly and blocks writes until a successful reload.

A process crash during copying may leave an unused staging directory. It cannot publish that incomplete copy as the destination. This is not a disk-durability guarantee or a migration of macOS security-scoped access grants.

`Tests/ShelfStorageLocationTests.swift` tests the actual filesystem implementation in temporary directories: fresh storage, byte-preserving copy, destination precedence after clearing/restart, injected partial-copy failure, cleanup, and successful retry. It does not read a user's Shelf or launch the app.

## Names intentionally retained

`scripts/legacy-name-allowlist.json` identifies active-source exceptions:

- boring.notch references that attribute the upstream project rather than advertise this fork as upstream.
- The legacy Shelf directory needed to find existing data.
- `/auth/boringNotch`, an external YouTube Music authorization client identifier. Renaming it without an authorization migration could invalidate saved access.
- A historical upstream download assertion in the archived-workflow tests.

Original author/copyright notices, license files, and upstream assets retain their provenance. Localization product keys were merged into a single `anotchup` entry; duplicate JSON keys are rejected by tests. Changed camera-preview translations remain marked for review.

## Publishing safety

Inherited release, nightly, update-feed website, and translation workflows live in `.github/disabled-workflows`, outside GitHub Actions' executable workflow directory. Historical upstream URLs and signed updater feeds are not renamed into fictional fork releases. The updater remains disabled.

Before distribution, review signing and XPC runtime behavior, dependency/asset licenses, bundled notices, corresponding source publication, updater configuration, and every publishing destination. This rename is not release clearance.

## Verification

Run `scripts/test-identity.sh` for static identity/localization checks and Shelf migration tests. `scripts/verify.sh --build` also runs component and workflow tests and compiles the unsigned app. Project/scheme enumeration and generated app/helper metadata were checked locally. No app launch, permission request, audio, user-data migration, or publication was performed.
