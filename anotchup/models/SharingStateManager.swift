//
//  SharingStateManager.swift
//  anotchup
//
//  Created by Alexander on 2025-10-10.
//

import AppKit
import Combine
import Foundation
import ShelfFeature

extension Notification.Name {
	static let sharingDidFinish = Notification.Name("com.anotchup.sharingDidFinish")
}

@MainActor
final class SharingStateManager: ObservableObject {
	static let shared = SharingStateManager()

	private var activeSessions: Int = 0 {
		didSet {
			let newValue = activeSessions > 0
			if newValue != preventNotchClose {
				preventNotchClose = newValue
				if !newValue {
					NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
				}
			}
		}
	}

	@Published var preventNotchClose: Bool = false

	private var activeDelegates: [UUID: SharingLifecycleDelegate] = [:]

	private init() {}
	
	func requestCloseIfReady() {
		if !preventNotchClose {
			NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
		}
	}

	func beginInteraction() {
		activeSessions += 1
	}

	func endInteraction() {
		if activeSessions > 0 { activeSessions -= 1 }
	}

	func makeDelegate(onEnd: (() -> Void)? = nil) -> SharingLifecycleDelegate {
		let id = UUID()
		let delegate = SharingLifecycleDelegate(id: id, onEnd: { [weak self] in
			onEnd?()
			self?.unregisterDelegate(id: id)
		}, onBegin: { [weak self] in
			self?.beginInteraction()
		}, onFinish: { [weak self] in
			self?.endInteraction()
		})
		activeDelegates[id] = delegate
		return delegate
	}

    func stop() {
        let delegates = Array(activeDelegates.values)
        delegates.forEach { $0.cancel() }
    }

	private func unregisterDelegate(id: UUID) {
		activeDelegates.removeValue(forKey: id)
	}
}

@MainActor
final class SharingLifecycleDelegate: NSObject, NSSharingServiceDelegate, NSSharingServicePickerDelegate {
	let id: UUID
    private let interaction: ShareInteraction

	init(id: UUID, onEnd: @escaping () -> Void, onBegin: @escaping () -> Void, onFinish: @escaping () -> Void) {
		self.id = id
        interaction = ShareInteraction(onBegin: onBegin, onFinish: onFinish, cleanup: onEnd)
	}
	
    func markPickerBegan() { interaction.beginPicker() }
    func markServiceBegan() { interaction.beginService() }
    func cancel() { interaction.finish() }
    private func finishIfNeeded() { interaction.finish() }

	// MARK: - NSSharingServicePickerDelegate

	func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
		if service == nil {
            interaction.pickerCanceled()
			return
		}

		service?.delegate = self
        interaction.beginService()
	}

	// MARK: - NSSharingServiceDelegate

	func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        interaction.beginService()
	}

	func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
		finishIfNeeded()
	}

	func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
		finishIfNeeded()
	}
}

