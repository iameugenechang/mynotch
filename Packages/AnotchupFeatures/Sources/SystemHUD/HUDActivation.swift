import Foundation

/// Permission checks are async; acquiring/releasing the native event tap is synchronous.
/// Only explicit user enablement may request authorization.
@MainActor
public final class HUDActivation {
    private let authorize: (Bool) async -> Bool
    private let activate: () -> Bool
    private let deactivate: () -> Void
    private let rejected: () -> Void
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private var stopped = false
    public private(set) var isActive = false

    public init(authorize: @escaping (Bool) async -> Bool, activate: @escaping () -> Bool,
                deactivate: @escaping () -> Void, rejected: @escaping () -> Void) {
        self.authorize = authorize
        self.activate = activate
        self.deactivate = deactivate
        self.rejected = rejected
    }

    public func setEnabled(_ enabled: Bool, promptIfNeeded: Bool = false) {
        guard !stopped else { return }
        revision = UUID()
        task?.cancel()
        task = nil
        guard enabled else {
            isActive = false
            deactivate()
            return
        }
        let expected = revision
        let authorize = authorize
        task = Task { [weak self] in
            let granted = await authorize(promptIfNeeded)
            guard let self, !Task.isCancelled, self.revision == expected, !self.stopped else { return }
            self.task = nil
            if granted && (self.isActive || self.activate()) {
                self.isActive = true
            } else {
                self.isActive = false
                self.deactivate()
                self.rejected()
            }
        }
    }

    public func stop() {
        setEnabled(false)
        stopped = true
    }

    deinit { task?.cancel() }
}
