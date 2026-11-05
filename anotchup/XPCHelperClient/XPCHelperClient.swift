import Foundation
import Cocoa
import AsyncXPCConnection
import SystemHUD

@MainActor
final class XPCHelperClient: NSObject {
    static let shared = XPCHelperClient()
    private final class Resource {
        private let serviceName = "com.iameugenechang.anotchup.AnotchupXPCHelper"
        let connection: NSXPCConnection
        let service: RemoteXPCService<AnotchupXPCHelperProtocol>
        init(disconnected: @escaping @MainActor () -> Void) {
            connection = NSXPCConnection(serviceName: serviceName)
            connection.interruptionHandler = { Task { @MainActor in disconnected() } }
            connection.invalidationHandler = { Task { @MainActor in disconnected() } }
            service = RemoteXPCService(connection: connection, remoteInterface: AnotchupXPCHelperProtocol.self)
            connection.resume()
        }
        deinit { connection.invalidate() }
    }
    private let owner = ConnectionOwner<Resource>(make: { Resource(disconnected: $0) }, close: { $0.connection.invalidate() })
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    private var monitorRevision = UUID()

    deinit { monitoringTask?.cancel() }

    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(name: .accessibilityAuthorizationChanged, object: nil, userInfo: ["granted": granted])
    }

    func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3) {
        stopMonitoringAccessibilityAuthorization()
        let revision = monitorRevision
        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                let authorized = await self?.readAuthorization(prompt: false)
                guard !Task.isCancelled, self?.monitorRevision == revision else { return }
                if let authorized { self?.notifyAuthorizationChange(authorized) }
                do { try await Task.sleep(for: .seconds(max(0.1, interval))) } catch { return }
            }
        }
    }

    func stopMonitoringAccessibilityAuthorization() {
        monitorRevision = UUID()
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    var isMonitoring: Bool { monitoringTask != nil }
    func stop() { stopMonitoringAccessibilityAuthorization(); owner.stop() }

    func requestAccessibilityAuthorization() {
        Task { [weak self] in _ = await self?.ensureAccessibilityAuthorization(promptIfNeeded: true) }
    }

    private func readAuthorization(prompt: Bool) async -> Bool? {
        try? await owner.perform { resource in
            try await resource.service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(prompt) { continuation.resume(returning: $0) }
            }
        }
    }

    func isAccessibilityAuthorized() async -> Bool { await ensureAccessibilityAuthorization(promptIfNeeded: false) }
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        let result = await readAuthorization(prompt: promptIfNeeded)
        if let result, !Task.isCancelled { notifyAuthorizationChange(result) }
        return result ?? false
    }

    func isKeyboardBrightnessAvailable() async -> Bool {
        (try? await owner.perform { resource in
            try await resource.service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { continuation.resume(returning: $0) }
            }
        }) ?? false
    }

    func currentKeyboardBrightness() async -> Float? {
        let value: NSNumber? = try? await owner.perform { resource in
            try await resource.service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { continuation.resume(returning: $0) }
            }
        }
        return value?.floatValue
    }

    func setKeyboardBrightness(_ value: Float) async -> Bool {
        guard value.isFinite else { return false }
        return (try? await owner.perform { resource in
            try await resource.service.withContinuation { service, continuation in
                service.setKeyboardBrightness(max(0, min(1, value))) { continuation.resume(returning: $0) }
            }
        }) ?? false
    }

    func isScreenBrightnessAvailable() async -> Bool {
        (try? await owner.perform { resource in
            try await resource.service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { continuation.resume(returning: $0) }
            }
        }) ?? false
    }

    func currentScreenBrightness() async -> Float? {
        let value: NSNumber? = try? await owner.perform { resource in
            try await resource.service.withContinuation { service, continuation in
                service.currentScreenBrightness { continuation.resume(returning: $0) }
            }
        }
        return value?.floatValue
    }

    func setScreenBrightness(_ value: Float) async -> Bool {
        guard value.isFinite else { return false }
        return (try? await owner.perform { resource in
            try await resource.service.withContinuation { service, continuation in
                service.setScreenBrightness(max(0, min(1, value))) { continuation.resume(returning: $0) }
            }
        }) ?? false
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}
