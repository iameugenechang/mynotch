import Combine
import Foundation

/// Owns native registrations and rejects deliveries already queued during teardown.
/// Delivery is always deferred to the main actor, even when posted on that actor.
@MainActor
public final class NotchNotificationSubscriptions {
    private var tokens: [AnyCancellable] = []
    public private(set) var stopped = false
    public init() {}

    public func observe(_ name: Notification.Name, center: NotificationCenter,
                        action: @escaping @MainActor () -> Void) {
        guard !stopped else { return }
        let observer = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.stopped else { return }
                action()
            }
        }
        tokens.append(AnyCancellable { center.removeObserver(observer) })
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        tokens.removeAll()
    }
}
