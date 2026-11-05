import Foundation

@main
struct ShelfTemporaryStorageTests {
    static func main() async throws {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("owned")
        let service = TemporaryFileStorageService(root: root)
        guard let file = await service.createTempFile(for: .data(Data([1, 2]), suggestedName: "../../escape.txt")) else {
            fatalError("temporary file creation failed")
        }
        precondition(file.lastPathComponent == "escape.txt")
        precondition(file.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path)
        let bytes = try Data(contentsOf: file)
        precondition(bytes == Data([1, 2]))
        let outside = sandbox.appendingPathComponent("owned-sibling")
        try Data([3]).write(to: outside)
        service.removeTemporaryFileIfNeeded(at: outside)
        precondition(FileManager.default.fileExists(atPath: outside.path))
        let link = file.deletingLastPathComponent().appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        service.removeTemporaryFileIfNeeded(at: link)
        precondition(FileManager.default.fileExists(atPath: outside.path))
        try FileManager.default.removeItem(at: link)
        service.removeTemporaryFileIfNeeded(at: file)
        precondition(!FileManager.default.fileExists(atPath: file.path))
        precondition(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        print("Shelf temporary-storage ownership checks passed")
    }
}
