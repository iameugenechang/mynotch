//
//  ShelfStateViewModel.swift
//  anotchup
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit
import Combine
import ShelfFeature

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = makeAppShelfState()
    private let collection: ShelfCollection<ShelfItem>
    private var observation: AnyCancellable?
    var items: [ShelfItem] { collection.items }
    var isLoading: Bool { collection.isLoading }
    var persistenceError: String? { collection.error }

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

    init(persistence: ShelfPersistenceService) {
        collection = ShelfCollection(load: persistence.load, save: persistence.save,
            identity: { $0.identityKey }, cleanup: { $0.cleanupStoredData() })
        observation = collection.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        pendingBookmarkUpdates.removeAll()
        collection.stop()
    }


    func add(_ newItems: [ShelfItem]) {
        collection.add(newItems)
    }

    func remove(_ item: ShelfItem) {
        collection.remove(id: item.id)
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        collection.update(id: item.id) {
            if case .file = $0.kind { $0.kind = .file(bookmark: bookmark) }
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self, !Task.isCancelled else { return }

            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                self.collection.update(id: itemID) {
                    if case .file = $0.kind { $0.kind = .file(bookmark: bookmarkData) }
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        Task { [weak self] in
            await self?.collection.importItems { await ShelfDropService.items(from: providers) }
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            await self.collection.validate { item in
                if case .file(let data) = item.kind { return await Bookmark(data: data).validate() }
                return true
            }
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
