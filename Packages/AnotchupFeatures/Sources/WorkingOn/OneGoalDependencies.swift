import Combine
import Foundation

/// Single-snapshot storage. Writes are immediately readable, not a disk-flush guarantee.
/// The component owns decoding, validation, and recovery of malformed snapshots.
@MainActor
public protocol OneGoalPersistence: AnyObject {
    func load() -> Data?
    func save(_ data: Data)
    func clear()
}

/// Delivers repeating ticks on the main actor, never inline during registration.
/// The interval must be finite and positive. Retain the token to keep ticks alive.
/// Cancel/release on the main actor; cancellation is idempotent and stops queued delivery.
@MainActor
public protocol CountdownScheduling {
    func schedule(every interval: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable
}
