import Combine
import NotchShell

@MainActor
public struct TaskNotchDelayScheduler: NotchDelayScheduling {
    public init() {}

    public func schedule(after delay: Duration,
                         _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        let task = Task { @MainActor in
            do { try await Task.sleep(for: max(.zero, delay)) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return AnyCancellable { task.cancel() }
    }
}
