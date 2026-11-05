import Foundation

/// Values read from one display at delivery time, not captured when a delay starts.
/// Shared navigation and native window effects are deliberately outside this type.
public struct NotchInteractionState: Sendable {
    public var isOpen: Bool
    public var isHovering: Bool
    public var isHoveringGoalControl: Bool
    public var isPreviewVisible: Bool
    public var opensOnHover: Bool
    public var isBatteryPopoverActive: Bool
    public var isSharing: Bool
    public var isEditorActive: Bool

    public init(isOpen: Bool, isHovering: Bool = false, isHoveringGoalControl: Bool = false,
                isPreviewVisible: Bool = false, opensOnHover: Bool = true,
                isBatteryPopoverActive: Bool = false, isSharing: Bool = false, isEditorActive: Bool = false) {
        self.isOpen = isOpen
        self.isHovering = isHovering
        self.isHoveringGoalControl = isHoveringGoalControl
        self.isPreviewVisible = isPreviewVisible
        self.opensOnHover = opensOnHover
        self.isBatteryPopoverActive = isBatteryPopoverActive
        self.isSharing = isSharing
        self.isEditorActive = isEditorActive
    }

    /// The common guard for every close source, including shortcuts and gestures.
    /// Deliberate editor dismissal must release editor protection before closing.
    public var canClose: Bool { !isSharing && !isEditorActive }

    public var canOpenOnHover: Bool {
        !isOpen && isHovering && !isHoveringGoalControl && !isPreviewVisible && opensOnHover
    }

    public var canCloseAfterHover: Bool {
        isOpen && !isBatteryPopoverActive && canClose
    }
}

/// One pending action in a display-local lane. Hover and shortcut auto-close use
/// separate instances, so pointer reentry does not cancel a shortcut countdown.
/// The host owns delays and cancels their tasks; tickets also reject callbacks
/// queued before cancellation. Mutate each instance on the host's main actor.
public struct NotchDelayedActionSession: Sendable {
    public enum Request: Equatable, Sendable { case open, leave, closeAfterProtection, shortcutClose }
    public enum Effect: Equatable, Sendable {
        case open, close
        case endHover(shouldClose: Bool)
    }
    public struct Ticket: Equatable, Sendable {
        fileprivate let id: UUID
        fileprivate let request: Request
    }

    private var pending: Ticket?

    public init() {}

    public mutating func schedule(_ request: Request) -> Ticket {
        let ticket = Ticket(id: UUID(), request: request)
        pending = ticket
        return ticket
    }

    public mutating func cancel() {
        pending = nil
    }

    /// A valid ticket is consumed even when current state suppresses its effect.
    /// A stale or foreign ticket cannot consume this display's current request.
    public mutating func fire(_ ticket: Ticket, state: NotchInteractionState) -> Effect? {
        guard pending == ticket else { return nil }
        pending = nil
        switch ticket.request {
        case .open:
            return state.canOpenOnHover ? .open : nil
        case .leave:
            return .endHover(shouldClose: state.canCloseAfterHover)
        case .closeAfterProtection:
            return !state.isHovering && state.canCloseAfterHover ? .close : nil
        case .shortcutClose:
            // Preserve deliberate shortcut behavior: pointer and battery guards
            // apply only to hover closes, but editor/sharing protection always applies.
            return state.isOpen && state.canClose ? .close : nil
        }
    }
}
