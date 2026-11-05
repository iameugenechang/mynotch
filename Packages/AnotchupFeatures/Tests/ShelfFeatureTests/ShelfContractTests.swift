import ShelfFeature
import ShelfAdapters
import XCTest

private struct Item: Codable, Identifiable, Equatable {
    let id: Int
    var value: String
}

final class ShelfContractTests: XCTestCase {
    @MainActor
    func testCollectionContractAgainstMemoryAndRealJSONPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = JSONShelfPersistence<Item>(fileURL: root.appendingPathComponent("items.json"))
        var memory: [Item] = []
        let backends: [(() throws -> [Item], ([Item]) throws -> Void)] = [
            ({ memory }, { memory = $0 }), (disk.load, disk.save)
        ]
        for (load, save) in backends {
            var cleaned: [Item] = []
            let collection = ShelfCollection(load: load, save: save, identity: { $0.value }, cleanup: { cleaned.append($0) })
            collection.add([Item(id: 1, value: "one"), Item(id: 2, value: "one"), Item(id: 3, value: "three")])
            XCTAssertEqual(collection.items.map(\.id), [1, 3])
            XCTAssertEqual(try load(), collection.items)
            collection.update(id: 1) { $0.value = "updated" }
            collection.remove(id: 3)
            XCTAssertEqual(cleaned.map(\.id), [3])
            XCTAssertEqual(try load(), collection.items)
            await collection.validate { _ in false }
            XCTAssertTrue(collection.items.isEmpty)
            XCTAssertEqual(cleaned.map(\.id), [3, 1])
            collection.stop()
            collection.add([Item(id: 4, value: "late")])
            XCTAssertTrue(try load().isEmpty)
        }
    }

    @MainActor
    func testFailedSaveDoesNotPublishOrDeleteResources() {
        enum Failure: Error { case disk }
        let original = Item(id: 1, value: "file")
        var cleaned = false
        let collection = ShelfCollection(load: { [original] }, save: { _ in throw Failure.disk },
            identity: { $0.value }, cleanup: { _ in cleaned = true })
        collection.remove(id: 1)
        XCTAssertEqual(collection.items, [original])
        XCTAssertFalse(cleaned)
        XCTAssertNotNil(collection.error)
    }

    @MainActor
    func testCorruptSnapshotIsNotOverwrittenAndReloadCanRecover() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("items.json")
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: file)
        let disk = JSONShelfPersistence<Item>(fileURL: file)
        let collection = ShelfCollection(load: disk.load, save: disk.save, identity: { $0.value }, cleanup: { _ in })
        collection.add([Item(id: 1, value: "new")])
        XCTAssertNotNil(collection.error)
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
        try disk.save([])
        collection.reload()
        collection.add([Item(id: 1, value: "new")])
        XCTAssertEqual(try disk.load(), collection.items)
    }

    @MainActor
    func testValidationCannotEraseConcurrentAdditionsOrBookmarkRefresh() async {
        var values = [Item(id: 1, value: "old bookmark")]
        let collection = ShelfCollection(load: { values }, save: { values = $0 }, identity: { $0.value }, cleanup: { _ in })
        await collection.validate { _ in
            collection.update(id: 1) { $0.value = "new bookmark" }
            collection.add([Item(id: 2, value: "new drop")])
            return false
        }
        XCTAssertEqual(collection.items.map(\.value), ["new bookmark", "new drop"])
    }

    @MainActor
    func testCanceledImportReleasesOnlyUnretainedResources() async {
        let held = Item(id: 1, value: "held")
        var cleaned: [Item] = []
        let collection = ShelfCollection(load: { [held] }, save: { _ in }, identity: { $0.value }, cleanup: { cleaned.append($0) })
        await collection.importItems {
            collection.stop()
            return [held, Item(id: 2, value: "abandoned")]
        }
        XCTAssertEqual(collection.items, [held])
        XCTAssertEqual(cleaned.map(\.id), [2])
        XCTAssertFalse(collection.isLoading)
    }
}
