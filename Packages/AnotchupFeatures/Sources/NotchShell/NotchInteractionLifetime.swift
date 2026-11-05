import Combine

/// One-shot main-actor delivery, never inline (including a zero delay).
/// Retain the token until delivery. Cancellation or token release suppresses
/// pending delivery. Negative delays behave as zero. No ordering across tokens
/// or exact wall-clock delivery time is promised.
@MainActor
public protocol NotchDelayScheduling {
    func schedule(after delay: Duration,
                  _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable
}

/// Owns delayed hover and shortcut work for one display, without native windows.
/// Hosts cancel on reopen/disappearance/lock transitions and permanently invalidate
/// on removal. State readers must be side-effect-free; callbacks should not retain
/// this owner. Effects may synchronously cancel or schedule further work.
@MainActor
public final class NotchInteractionLifetime {
    public enum Lane: Hashable, Sendable { case hover, shortcut }
    public private(set) var isInvalidated = false

    private struct Pending {
        var policy: NotchDelayedActionSession
        let ticket: NotchDelayedActionSession.Ticket
        let token: AnyCancellable
        let state: @MainActor () -> NotchInteractionState
        let apply: @MainActor (NotchDelayedActionSession.Effect) -> Void
    }

    private let scheduler: any NotchDelayScheduling
    private var pending: [Lane: Pending] = [:]

    public init(scheduler: any NotchDelayScheduling) {
        self.scheduler = scheduler
    }

    public func schedule(_ request: NotchDelayedActionSession.Request, after delay: Duration,
                         state: @escaping @MainActor () -> NotchInteractionState,
                         apply: @escaping @MainActor (NotchDelayedActionSession.Effect) -> Void) {
        guard !isInvalidated else { return }
        let lane: Lane = request == .shortcutClose ? .shortcut : .hover
        cancel(lane)
        var policy = NotchDelayedActionSession()
        let ticket = policy.schedule(request)
        let token = scheduler.schedule(after: delay) { [weak self] in
            self?.deliver(ticket, in: lane)
        }
        pending[lane] = Pending(policy: policy, ticket: ticket, token: token, state: state, apply: apply)
    }

    public func cancel(_ lane: Lane) {
        // Remove first so even a queued callback cannot consume newer work.
        let removed = pending.removeValue(forKey: lane)
        removed?.token.cancel()
    }

    public func cancelAll() {
        let removed = pending
        pending.removeAll()
        removed.values.forEach { $0.token.cancel() }
    }

    /// Terminal: stale host events cannot restart a removed display's work.
    public func invalidate() {
        isInvalidated = true
        cancelAll()
    }

    private func deliver(_ ticket: NotchDelayedActionSession.Ticket, in lane: Lane) {
        guard !isInvalidated, var delivery = pending[lane], delivery.ticket == ticket else { return }
        pending.removeValue(forKey: lane)
        delivery.token.cancel()
        if let effect = delivery.policy.fire(ticket, state: delivery.state()) {
            delivery.apply(effect)
        }
    }
}
