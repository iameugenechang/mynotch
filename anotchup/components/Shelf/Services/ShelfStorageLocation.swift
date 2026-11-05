import Foundation

/// Copies legacy Shelf data once without deleting it. The destination wins on
/// subsequent launches, including an intentionally empty shelf.
enum ShelfStorageLocation {
    static func current(in support: URL) -> URL {
        support.appendingPathComponent("anotchup/Shelf", isDirectory: true)
    }

    static func legacy(in support: URL) -> URL {
        support.appendingPathComponent("boringNotch/Shelf", isDirectory: true)
    }

    static func prepare(in support: URL, fileManager: FileManager = .default,
                        copy: ((URL, URL) throws -> Void)? = nil) throws -> URL {
        let destination = current(in: support)
        guard !fileManager.fileExists(atPath: destination.path) else { return destination }
        let source = legacy(in: support)
        guard fileManager.fileExists(atPath: source.path) else {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            return destination
        }
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".shelf-migration-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }
        if let copy {
            try copy(source, staging)
        } else {
            try fileManager.copyItem(at: source, to: staging)
        }
        // Publish only a complete copy. A failed copy must not shadow legacy data.
        try fileManager.moveItem(at: staging, to: destination)
        return destination
    }
}
