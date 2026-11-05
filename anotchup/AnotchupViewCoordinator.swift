//
//  AnotchupViewCoordinator.swift
//  anotchup
//
//  Created by Alexander on 2024-11-20.
//

import AppKit
import Combine
import Defaults
import NotchShell
import NotchShellAdapters
import SwiftUI
import SystemHUD

enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
}

@MainActor
class AnotchupViewCoordinator: ObservableObject {
    static let shared = makeAppViewCoordinator()

    let navigation = NotchNavigation()
    private var navigationObservation: AnyCancellable?
    var currentView: NotchViews {
        get { navigation.selection }
        set { navigation.select(newValue) }
    }
    @Published var helloAnimationRunning: Bool = false
    private let previewLifetime = NotchInteractionLifetime(scheduler: TaskNotchDelayScheduler())
    private let hudActivation: HUDActivation

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("currentMicStatus") var currentMicStatus: Bool = true

    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if ShelfStateViewModel.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }

    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @Default(.hudReplacement) var hudReplacement: Bool
    
    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?
    
    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    @Published var optionKeyPressed: Bool = true
    private var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?

    init(hudActivation: HUDActivation) {
        self.hudActivation = hudActivation
        navigationObservation = navigation.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }
        
        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""
        // Observe changes to accessibility authorization and react accordingly
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hudActivation.setEnabled(Defaults[.hudReplacement])
            }
        }

        // Observe changes to hudReplacement
        hudReplacementCancellable = Defaults.publisher(.hudReplacement, options: [])
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    // Subscription changes represent explicit preference changes;
                    // initial startup is handled below without prompting.
                    self.hudActivation.setEnabled(change.newValue, promptIfNeeded: change.newValue)
                }
            }

        helloAnimationRunning = firstLaunch
        hudActivation.setEnabled(Defaults[.hudReplacement])
    }
    
    @objc func sneakPeekEvent(_ notification: Notification) {
        guard let data = notification.userInfo?.values.compactMap({ $0 as? Data }).first,
              let message = try? HUDMessage.decode(data) else { return }
        let contentType: SneakContentType
        switch message.kind {
        case .brightness: contentType = .brightness
        case .volume: contentType = .volume
        case .backlight: contentType = .backlight
        case .mic: contentType = .mic
        }
        toggleSneakPeek(status: message.show, type: contentType, value: CGFloat(message.value), icon: message.icon)
    }

    func toggleSneakPeek(
        status: Bool, type: SneakContentType, duration: TimeInterval = 1.5, value: CGFloat = 0,
        icon: String = ""
    ) {
        sneakPeekDuration = duration
        if type != .music {
            // close()
            if !Defaults[.hudReplacement] {
                return
            }
        }
        withAnimation(.smooth) {
            self.sneakPeek = .init(show: status, type: type, value: value, icon: icon)
        }

        if type == .mic {
            currentMicStatus = value == 1
        }
    }

    private var sneakPeekDuration: TimeInterval = 1.5
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        previewLifetime.schedule(.hideCompactPreview, after: .seconds(duration), state: { [weak self] in
            NotchInteractionState(isOpen: false, isPreviewVisible: self?.sneakPeek.show == true)
        }, apply: { [weak self] _ in
            self?.toggleSneakPeek(status: false, type: .music)
        })
    }

    func stop() {
        hudReplacementCancellable?.cancel()
        if let accessibilityObserver { NotificationCenter.default.removeObserver(accessibilityObserver) }
        accessibilityObserver = nil
        hudActivation.stop()
        cancelPreviews()
        previewLifetime.invalidate()
    }

    func cancelPreviews() {
        previewLifetime.cancelAll()
        sneakPeek.show = false
        expandingView.show = false
    }

    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                previewLifetime.cancel(.compactPreview)
            }
        }
    }

    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium
    ) {
        withAnimation(.smooth) {
            self.expandingView = .init(show: status, type: type, value: value, browser: browser)
        }
    }

    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                let duration: TimeInterval = (expandingView.type == .download ? 2 : 3)
                previewLifetime.schedule(.hideExpandedPreview, after: .seconds(duration), state: { [weak self] in
                    NotchInteractionState(isOpen: false, isPreviewVisible: self?.expandingView.show == true)
                }, apply: { [weak self] _ in
                    guard let self else { return }
                    self.toggleExpandingView(status: false, type: self.expandingView.type)
                })
            } else {
                previewLifetime.cancel(.expandedPreview)
            }
        }
    }
    
    func showEmpty() {
        currentView = .home
    }
}
