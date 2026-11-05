//
//  ShelfPersistenceService.swift
//  anotchup
//
//  Created by Alexander on 2025-09-24.
//

import Foundation
import ShelfAdapters

@MainActor
final class ShelfPersistenceService {
    private let storage: JSONShelfPersistence<ShelfItem>

    init(fileURL: URL) { storage = JSONShelfPersistence(fileURL: fileURL) }

    convenience init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = support ?? fm.temporaryDirectory
        let dir: URL
        do { dir = try ShelfStorageLocation.prepare(in: root, fileManager: fm) }
        catch {
            let legacy = ShelfStorageLocation.legacy(in: root)
            dir = fm.fileExists(atPath: legacy.path) ? legacy : ShelfStorageLocation.current(in: root)
            print("Could not migrate Shelf storage: \(error.localizedDescription)")
        }
        self.init(fileURL: dir.appendingPathComponent("items.json"))
    }

    func load() throws -> [ShelfItem] { try storage.load() }
    func save(_ items: [ShelfItem]) throws { try storage.save(items) }
}
