//
//  WebcamManager.swift
//  anotchup
//
//  Created by Harsh Vardhan  Goswami  on 19/08/24.
//
import AVFoundation
import CameraFeature
import Combine
import SwiftUI

/// Native preview facade. Capture-request ownership lives in CameraSession.
@MainActor
final class WebcamManager: ObservableObject {
    static let shared = makeAppWebcamManager()
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    @Published private(set) var isSessionRunning = false
    @Published private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published private(set) var cameraAvailable = false
    @Published private(set) var isRequestingAuthorization = false
    let session: CameraSession
    private var subscriptions = Set<AnyCancellable>()

    init(device: AVCameraDevice, notifications: NotificationCenter = .default) {
        session = CameraSession(device: device)
        device.$previewLayer.sink { [weak self] in self?.previewLayer = $0 }.store(in: &subscriptions)
        session.$phase.sink { [weak self] in self?.isSessionRunning = $0 == .running }.store(in: &subscriptions)
        session.$available.sink { [weak self] in self?.cameraAvailable = $0 }.store(in: &subscriptions)
        session.$requestingAuthorization.sink { [weak self] in self?.isRequestingAuthorization = $0 }.store(in: &subscriptions)
        session.$authorization.sink { [weak self] in
            switch $0 {
            case .unknown: self?.authorizationStatus = .notDetermined
            case .allowed: self?.authorizationStatus = .authorized
            case .denied: self?.authorizationStatus = .denied
            case .restricted: self?.authorizationStatus = .restricted
            }
        }.store(in: &subscriptions)
        for name in [NSNotification.Name.AVCaptureDeviceWasConnected, .AVCaptureDeviceWasDisconnected] {
            notifications.publisher(for: name).sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    if name == .AVCaptureDeviceWasDisconnected { self?.session.stop() }
                    self?.session.refresh()
                }
            }.store(in: &subscriptions)
        }
    }

    func checkAndRequestVideoAuthorization() {
        Task { [weak self] in await self?.session.requestAuthorization() }
    }
    func checkCameraAvailability() { session.refresh() }
    func startSession() { session.start() }
    func stopSession() { session.stop() }
    func shutdown() { session.shutdown(); subscriptions.removeAll(); previewLayer = nil; isSessionRunning = false }
}

@MainActor
final class AVCameraDevice: CameraDevice {
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private let worker = CaptureWorker()

    var authorization: CameraAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .unknown
        }
    }
    var isAvailable: Bool {
        !AVCaptureDevice.DiscoverySession(deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video, position: .unspecified).devices.isEmpty
    }
    func requestAuthorization() async -> CameraAuthorization {
        guard authorization == .unknown else { return authorization }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return authorization
    }
    func start() async throws {
        guard authorization == .allowed else { throw CaptureError.denied }
        let capture = try await worker.start()
        let layer = AVCaptureVideoPreviewLayer(session: capture)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
    }
    func stop() async {
        previewLayer = nil
        await worker.stop()
    }
}

private enum CaptureError: Error { case denied, unavailable, inputRejected }

/// All capture mutation is serialized here, including partial-setup cleanup.
private final class CaptureWorker {
    private let queue = DispatchQueue(label: "Anotchup.Camera.Capture", qos: .userInitiated)
    private var session: AVCaptureSession?

    func start() async throws -> AVCaptureSession {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let session { continuation.resume(returning: session); return }
                do {
                    guard let device = AVCaptureDevice.DiscoverySession(
                        deviceTypes: [.external, .builtInWideAngleCamera], mediaType: .video,
                        position: .unspecified).devices.first else { throw CaptureError.unavailable }
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    let input = try AVCaptureDeviceInput(device: device)
                    let capture = AVCaptureSession()
                    guard capture.canAddInput(input) else { throw CaptureError.inputRejected }
                    capture.beginConfiguration()
                    capture.sessionPreset = .high
                    capture.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.setSampleBufferDelegate(nil, queue: nil)
                    if capture.canAddOutput(output) { capture.addOutput(output) }
                    capture.commitConfiguration()
                    capture.startRunning()
                    guard capture.isRunning else {
                        Self.release(capture)
                        throw CaptureError.unavailable
                    }
                    session = capture
                    continuation.resume(returning: capture)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let session { Self.release(session) }
                session = nil
                continuation.resume()
            }
        }
    }

    private static func release(_ session: AVCaptureSession) {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.commitConfiguration()
    }

    deinit {
        if let session { queue.async { Self.release(session) } }
    }
}
