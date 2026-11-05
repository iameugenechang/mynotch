import Foundation

/// One sharing operation owns one protection count and releases resources once.
/// Completion comes from the adapter, never an arbitrary elapsed-time timeout.
@MainActor
public final class ShareInteraction {
    public enum Phase { case pending, picker, service, finished }
    public private(set) var phase: Phase = .pending
    private var began = false
    private let onBegin: () -> Void
    private let onFinish: () -> Void
    private let cleanup: () -> Void

    public init(onBegin: @escaping () -> Void, onFinish: @escaping () -> Void, cleanup: @escaping () -> Void) {
        self.onBegin = onBegin
        self.onFinish = onFinish
        self.cleanup = cleanup
    }

    public func beginPicker() {
        guard phase == .pending else { return }
        phase = .picker
        beginOnce()
    }

    public func beginService() {
        guard phase != .finished else { return }
        phase = .service
        beginOnce()
    }

    public func pickerCanceled() {
        guard phase != .service else { return }
        finish()
    }

    /// Success, failure, explicit cancellation, and host shutdown share cleanup.
    public func finish() {
        guard phase != .finished else { return }
        phase = .finished
        if began { onFinish() }
        cleanup()
    }

    private func beginOnce() {
        guard !began else { return }
        began = true
        onBegin()
    }
}
