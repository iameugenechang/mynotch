import Combine
import Foundation

/// Persistence commits precede publication and resource cleanup. A failed load
/// blocks mutation until an explicit successful reload, so corruption is not erased.
@MainActor
public final class ShelfCollection<Item: Identifiable & Equatable>: ObservableObject {
    @Published public private(set) var items: [Item] = []
    @Published public private(set) var error: String?
    @Published public private(set) var isLoading = false
    private let loadSnapshot: () throws -> [Item]
    private let saveSnapshot: ([Item]) throws -> Void
    private let identity: (Item) -> String
    private let cleanup: (Item) -> Void
    private var canWrite = false
    private var stopped = false
    private var loads = 0

    public init(load: @escaping () throws -> [Item], save: @escaping ([Item]) throws -> Void,
                identity: @escaping (Item) -> String, cleanup: @escaping (Item) -> Void) {
        loadSnapshot = load
        saveSnapshot = save
        self.identity = identity
        self.cleanup = cleanup
        reload()
    }

    public func reload() {
        guard !stopped else { return }
        do { items = try loadSnapshot(); error = nil; canWrite = true }
        catch { self.error = String(describing: error); canWrite = false }
    }

    @discardableResult
    private func commit(_ updated: [Item]) -> Bool {
        guard !stopped, canWrite else { return false }
        do { try saveSnapshot(updated); items = updated; error = nil; return true }
        catch { self.error = String(describing: error); return false }
    }

    public func add(_ incoming: [Item]) {
        guard !incoming.isEmpty else { return }
        var updated = items
        var seen = Set(updated.map(identity))
        for item in incoming where seen.insert(identity(item)).inserted { updated.append(item) }
        if updated != items { commit(updated) }
    }

    public func remove(id: Item.ID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if commit(items.filter { $0.id != id }) { cleanup(item) }
    }

    public func update(id: Item.ID, _ transform: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items
        transform(&updated[index])
        if updated != items { commit(updated) }
    }

    public func validate(_ isValid: (Item) async -> Bool) async {
        guard !stopped else { return }
        let snapshot = items
        var invalid: [Item] = []
        for item in snapshot {
            if !(await isValid(item)) { invalid.append(item) }
            guard !stopped, !Task.isCancelled else { return }
        }
        // Preserve additions and refreshed bookmarks made during validation.
        let removed = items.filter { invalid.contains($0) }
        guard !removed.isEmpty else { return }
        if commit(items.filter { !removed.contains($0) }) { removed.forEach(cleanup) }
    }

    public func importItems(_ produce: () async -> [Item]) async {
        guard !stopped else { return }
        loads += 1
        isLoading = true
        let incoming = await produce()
        loads -= 1
        isLoading = !stopped && loads > 0
        guard !stopped, !Task.isCancelled else {
            // Only release resources not also referenced by the live collection.
            let retained = Set(items.map(identity))
            incoming.filter { !retained.contains(identity($0)) }.forEach(cleanup)
            return
        }
        add(incoming)
        let retained = Set(items.map(identity))
        incoming.filter { !retained.contains(identity($0)) }.forEach(cleanup)
    }

    public func stop() { stopped = true; isLoading = false }
}
