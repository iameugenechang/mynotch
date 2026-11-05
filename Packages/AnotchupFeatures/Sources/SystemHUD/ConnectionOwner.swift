import Foundation

/// Owns one connection generation. Loss callbacks must be delivered after factory
/// return, on the main actor. Old callbacks cannot close a replacement connection.
@MainActor
public final class ConnectionOwner<Resource> {
    public struct Lease {
        public let id: UUID
        public let resource: Resource
    }
    public enum Failure: Error { case stopped, stale }
    private let make: (@escaping @MainActor () -> Void) throws -> Resource
    private let close: (Resource) -> Void
    private var current: Lease?
    private var stopped = false

    public init(make: @escaping (@escaping @MainActor () -> Void) throws -> Resource,
                close: @escaping (Resource) -> Void) {
        self.make = make
        self.close = close
    }

    public func acquire() throws -> Lease {
        guard !stopped else { throw Failure.stopped }
        if let current { return current }
        let id = UUID()
        let resource = try make { [weak self] in self?.lost(id) }
        let lease = Lease(id: id, resource: resource)
        current = lease
        return lease
    }

    public func isCurrent(_ lease: Lease) -> Bool { !stopped && current?.id == lease.id }

    public func perform<Value>(_ operation: (Resource) async throws -> Value) async throws -> Value {
        let lease = try acquire()
        let value = try await operation(lease.resource)
        try Task.checkCancellation()
        guard isCurrent(lease) else { throw Failure.stale }
        return value
    }

    public func disconnect() {
        let old = current
        current = nil
        if let old { close(old.resource) }
    }

    public func stop() { stopped = true; disconnect() }

    private func lost(_ id: UUID) {
        guard current?.id == id else { return }
        disconnect()
    }
}
