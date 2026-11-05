import Foundation

/// One JSON array per file, atomically replaced. No user paths are chosen here.
/// Missing files are empty; invalid snapshots and I/O failures throw, preserving bytes.
@MainActor
public final class JSONShelfPersistence<Item: Codable> {
    public let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    public func load() throws -> [Item] {
        do { return try decoder.decode([Item].self, from: Data(contentsOf: fileURL)) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return []
        }
    }
    public func save(_ items: [Item]) throws {
        let data = try encoder.encode(items)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
