import Foundation

@main
struct ShelfStorageLocationTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("anotchup-migration-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let fresh = root.appendingPathComponent("fresh")
        let created = try ShelfStorageLocation.prepare(in: fresh)
        precondition(created == ShelfStorageLocation.current(in: fresh))
        precondition(fm.fileExists(atPath: created.path))

        let existing = root.appendingPathComponent("existing")
        let legacy = ShelfStorageLocation.legacy(in: existing)
        try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        let bytes = Data("[{\"bookmark\":\"preserve opaque bytes\"}]".utf8)
        try bytes.write(to: legacy.appendingPathComponent("items.json"))
        let migrated = try ShelfStorageLocation.prepare(in: existing)
        let migratedBytes = try Data(contentsOf: migrated.appendingPathComponent("items.json"))
        let originalBytes = try Data(contentsOf: legacy.appendingPathComponent("items.json"))
        precondition(migratedBytes == bytes && originalBytes == bytes)
        // New data, including clearing the shelf, must not be overwritten on restart.
        try Data("[]".utf8).write(to: migrated.appendingPathComponent("items.json"))
        let restarted = try ShelfStorageLocation.prepare(in: existing)
        let restartedBytes = try Data(contentsOf: restarted.appendingPathComponent("items.json"))
        precondition(restartedBytes == Data("[]".utf8))

        let failure = root.appendingPathComponent("failure")
        let failureLegacy = ShelfStorageLocation.legacy(in: failure)
        try fm.createDirectory(at: failureLegacy, withIntermediateDirectories: true)
        try bytes.write(to: failureLegacy.appendingPathComponent("items.json"))
        enum SimulatedFailure: Error { case interrupted }
        do {
            _ = try ShelfStorageLocation.prepare(in: failure) { _, staging in
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                try Data("partial".utf8).write(to: staging.appendingPathComponent("items.json"))
                throw SimulatedFailure.interrupted
            }
            preconditionFailure("copy failure should propagate")
        } catch SimulatedFailure.interrupted { }
        precondition(!fm.fileExists(atPath: ShelfStorageLocation.current(in: failure).path))
        let stagingFiles = try fm.contentsOfDirectory(atPath: failure.appendingPathComponent("anotchup").path)
        precondition(stagingFiles.isEmpty)
        let retried = try ShelfStorageLocation.prepare(in: failure)
        let retriedBytes = try Data(contentsOf: retried.appendingPathComponent("items.json"))
        precondition(retriedBytes == bytes)
        print("Shelf storage migration: fresh, copy, restart, failure, and retry checks passed")
    }
}
