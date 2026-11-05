import Foundation

/// Owns one native resource per selected display slot. Native construction is an effect.
@MainActor
public final class NotchDisplayLifecycle<Resource> {
    public private(set) var resources: [String: Resource] = [:]
    public private(set) var stopped = false
    private let cancel: (Resource) -> Void
    private let destroy: (Resource) -> Void

    public init(cancel: @escaping (Resource) -> Void, destroy: @escaping (Resource) -> Void) {
        self.cancel = cancel
        self.destroy = destroy
    }

    public func reconcile(ids: Set<String>, make: (String) -> Resource, update: (String, Resource) -> Void) {
        guard !stopped else { return }
        for id in resources.keys.sorted() where !ids.contains(id) {
            if let resource = resources.removeValue(forKey: id) { destroy(resource) }
        }
        for id in ids.sorted() {
            if resources[id] == nil { resources[id] = make(id) }
            if let resource = resources[id] { update(id, resource) }
        }
    }

    public func cancelAll() { resources.values.forEach(cancel) }
    public func removeAll() {
        let removed = resources
        resources.removeAll()
        removed.values.forEach(destroy)
    }
    public func stop() {
        guard !stopped else { return }
        stopped = true
        removeAll()
    }

    public static func desiredIDs(available: Set<String>, selected: String?, allDisplays: Bool,
                                  locked: Bool, showOnLockScreen: Bool) -> Set<String> {
        guard !locked || showOnLockScreen else { return [] }
        if allDisplays { return available }
        guard let selected, available.contains(selected) else { return [] }
        return [selected]
    }
}

public enum NotchGeometry {
    public static func origin(screen: CGRect, window: CGSize) -> CGPoint {
        CGPoint(x: screen.origin.x + (screen.size.width - window.width) / 2,
                y: screen.origin.y + screen.size.height - window.height)
    }
    public static func contains(_ point: CGPoint, screen: CGRect, notch: CGSize) -> Bool {
        let middle = screen.origin.x + screen.size.width / 2
        return point.y >= screen.origin.y + screen.size.height - notch.height
            && point.x >= middle - notch.width / 2 && point.x <= middle + notch.width / 2
    }
    public static func closedHeight(height: Double, hide: Bool, hasCutout: Bool) -> Double {
        hide && !hasCutout ? 0 : height
    }
    public static func chinHeight(menuBar: Double, closed: Double, hiddenTitleBar: Bool, isOpen: Bool) -> Double {
        hiddenTitleBar && !isOpen && closed > 0 ? max(0, menuBar - closed) : 0
    }
}
