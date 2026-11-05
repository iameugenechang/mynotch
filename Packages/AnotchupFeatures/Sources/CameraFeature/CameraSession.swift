import Combine
import Foundation

public enum CameraAuthorization: Equatable { case unknown, allowed, denied, restricted }
public enum CameraPhase: Equatable { case idle, unavailable, denied, starting, running, stopping, stopped; case failed(String) }

/// Native implementations serialize capture operations. Start must either acquire
/// a running capture resource or throw; stop must be idempotent and release it.
@MainActor
public protocol CameraDevice: AnyObject {
    var authorization: CameraAuthorization { get }
    var isAvailable: Bool { get }
    func requestAuthorization() async -> CameraAuthorization
    func start() async throws
    func stop() async
}

/// One app-wide capture request, matching the existing mirror toggle behavior.
/// Stop during start is reconciled after acquisition, never lost to a late callback.
@MainActor
public final class CameraSession: ObservableObject {
    @Published public private(set) var authorization: CameraAuthorization
    @Published public private(set) var available: Bool
    @Published public private(set) var phase: CameraPhase = .idle
    @Published public private(set) var requestingAuthorization = false
    private let device: any CameraDevice
    private var requested = false
    private var running = false
    private var terminal = false
    private var worker: Task<Void, Never>?
    private var authorizationTask: Task<CameraAuthorization, Never>?

    public init(device: any CameraDevice) {
        self.device = device
        authorization = device.authorization
        available = device.isAvailable
    }

    public func refresh() {
        guard !terminal else { return }
        authorization = device.authorization
        available = device.isAvailable
        if authorization != .allowed || !available { requested = false }
        reconcile()
    }

    public func requestAuthorization() async {
        guard !terminal else { return }
        if authorizationTask == nil {
            requestingAuthorization = true
            let device = self.device
            authorizationTask = Task { await device.requestAuthorization() }
        }
        let result = await authorizationTask!.value
        guard !terminal else { return }
        authorizationTask = nil
        requestingAuthorization = false
        authorization = result
        available = device.isAvailable
        reconcile()
    }

    public func start() {
        guard !terminal else { return }
        authorization = device.authorization
        available = device.isAvailable
        guard authorization == .allowed else { phase = .denied; return }
        guard available else { phase = .unavailable; return }
        requested = true
        reconcile()
    }

    public func stop() { requested = false; reconcile() }

    public func shutdown() {
        terminal = true
        requested = false
        authorizationTask?.cancel()
        authorizationTask = nil
        requestingAuthorization = false
        reconcile()
    }

    private func reconcile() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while self.running != self.requested {
                if self.requested {
                    self.phase = .starting
                    do {
                        try await self.device.start()
                        self.running = true
                        if self.requested { self.phase = .running }
                    } catch {
                        // Even a partial native acquisition must be released.
                        await self.device.stop()
                        self.running = false
                        self.requested = false
                        self.phase = self.terminal ? .stopped : .failed(String(describing: error))
                        self.worker = nil
                        return
                    }
                } else {
                    self.phase = .stopping
                    await self.device.stop()
                    self.running = false
                }
            }
            self.phase = self.terminal ? .stopped : self.running ? .running : .idle
            self.worker = nil
        }
    }
}
