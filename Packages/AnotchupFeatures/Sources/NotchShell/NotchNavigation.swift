import Combine
import Foundation

public enum NotchTab: Equatable, Sendable { case home, shelf, goal }

/// One shared tab selection, with display-local editor requests and one native
/// focus owner. Display IDs identify lifetimes, not physical screen names.
@MainActor
public final class NotchNavigation: ObservableObject {
    @Published public private(set) var selection: NotchTab = .home
    @Published public private(set) var focusedEditor: UUID?
    private var displays: Set<UUID> = []
    private var editors: Set<UUID> = []

    public init() {}
    public func register(_ display: UUID) { displays.insert(display) }
    public func remove(_ display: UUID) {
        displays.remove(display)
        editors.remove(display)
        if focusedEditor == display { focusedEditor = nil }
    }
    public func select(_ tab: NotchTab) {
        selection = tab
        if tab != .goal {
            editors.removeAll()
            focusedEditor = nil
        }
    }
    public func requestEditor(_ active: Bool, on display: UUID) {
        guard displays.contains(display) else { return }
        if active { editors.insert(display) } else {
            editors.remove(display)
            if focusedEditor == display { focusedEditor = nil }
        }
    }
    public func becameKey(_ display: UUID) {
        guard editors.contains(display) else { return }
        focusedEditor = display
    }
    /// Returns whether losing native focus may reset the shared tab.
    public func resignedKey(_ display: UUID) -> Bool {
        guard displays.contains(display) else { return false }
        requestEditor(false, on: display)
        return editors.isEmpty
    }
    public func close(resetSelection: Bool, shelfHasItems: Bool,
                      opensShelf: Bool, keepsLastTab: Bool) {
        guard resetSelection else { return }
        if shelfHasItems && opensShelf { select(.shelf) }
        else if !keepsLastTab { select(.home) }
    }
}
