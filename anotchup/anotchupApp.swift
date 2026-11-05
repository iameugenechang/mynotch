//
//  anotchupApp.swift
//  anotchupApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AppIdentity
import AppIdentityAdapters
import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import NotchShell
import NotchShellAdapters
import Sparkle
import SwiftUI
import SystemHUD
import WorkingOn
import WorkingOnAdapters

/// Migration must precede property wrappers and app-delegate/service construction.
@main
enum AnotchupBootstrap {
    @MainActor
    static func main() {
        do {
            try PreferencesMigration.run(
                source: UserDefaultsDomain(name: "com.iameugenechang.mynotch"),
                destination: UserDefaultsDomain(name: "com.iameugenechang.anotchup"))
        } catch {
            // Do not start services with an unverified, apparently empty domain.
            fputs("anotchup preference migration failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
        AnotchupApp.main()
    }
}

struct AnotchupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("anotchup", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            Link("anotchup on GitHub", destination: URL(string: "https://github.com/iameugenechang/mynotch")!)
            Divider()
            Button("Restart anotchup") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

@MainActor
struct NotchViewDependencies {
    let coordinator: AnotchupViewCoordinator
    let detector: FullscreenMediaDetector
    let refreshMedia: () -> Void
    let isSharing: () -> Bool
    let shelfHasItems: () -> Bool
    let toggleCamera: (AnotchupViewModel) -> Void
}

@MainActor
func makeAppNotchDependencies() -> NotchViewDependencies {
    NotchViewDependencies(coordinator: .shared, detector: .shared,
        refreshMedia: { MusicManager.shared.forceUpdate() },
        isSharing: { SharingStateManager.shared.preventNotchClose },
        shelfHasItems: { !ShelfStateViewModel.shared.isEmpty },
        toggleCamera: { model in
            let camera = WebcamManager.shared
            guard !camera.isRequestingAuthorization else { return }
            switch camera.authorizationStatus {
            case .authorized:
                if camera.isSessionRunning {
                    camera.stopSession()
                    model.isCameraExpanded = false
                } else if camera.cameraAvailable {
                    camera.startSession()
                    model.isCameraExpanded = true
                }
            case .notDetermined: camera.checkAndRequestVideoAuthorization()
            case .denied, .restricted:
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                defer { NSApp.setActivationPolicy(.accessory); NSApp.deactivate() }
                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            @unknown default: break
            }
        })
}

@MainActor
func makeAppViewCoordinator() -> AnotchupViewCoordinator {
    AnotchupViewCoordinator(hudActivation: HUDActivation(
        authorize: { await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: $0) },
        activate: { MediaKeyInterceptor.shared.startAuthorized() },
        deactivate: { MediaKeyInterceptor.shared.stop() },
        rejected: { if Defaults[.hudReplacement] { Defaults[.hudReplacement] = false } }))
}

@MainActor
func makeAppShelfState() -> ShelfStateViewModel {
    ShelfStateViewModel(persistence: ShelfPersistenceService())
}

@MainActor
func makeAppWebcamManager() -> WebcamManager {
    WebcamManager(device: AVCameraDevice())
}

@MainActor
func makeAppCalendarManager() -> CalendarManager {
    CalendarManager(service: CalendarService())
}

/// Native media construction and cross-feature effects stay at composition.
@MainActor
func makeAppMusicManager() -> MusicManager {
    MusicManager(providerFactory: { type, deprecated in
        switch type {
        case .nowPlaying: return deprecated ? nil : NowPlayingController()
        case .appleMusic: return AppleMusicController()
        case .spotify: return SpotifyController()
        case .youtubeMusic: return YouTubeMusicController()
        }
    }, onPlaybackActivity: {
        guard Defaults[.enableSneakPeek] else { return }
        let coordinator = AnotchupViewCoordinator.shared
        if Defaults[.sneakPeekStyles] == .standard {
            coordinator.toggleSneakPeek(status: true, type: .music)
        } else {
            coordinator.toggleExpandingView(status: true, type: .music)
        }
    })
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // App-owned feature instance, shared by every display's view tree.
    private let goalStore = OneGoalStore(
        persistence: UserDefaultsOneGoalPersistence(defaults: .standard),
        scheduler: RunLoopCountdownScheduler(), clock: { Date() })

    var statusItem: NSStatusItem?
    private struct DisplayResource {
        let window: NSWindow
        let model: AnotchupViewModel
        let observer: NSObjectProtocol
    }
    private let displays = NotchDisplayLifecycle<DisplayResource>(
        cancel: { $0.model.cancelDelayedInteractions() },
        destroy: { resource in
            resource.model.destroy()
            NotificationCenter.default.removeObserver(resource.observer)
            resource.window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(resource.window)
        })
    var windows: [String: NSWindow] { displays.resources.mapValues(\.window) }
    var viewModels: [String: AnotchupViewModel] { displays.resources.mapValues(\.model) }
    var window: NSWindow? { Defaults[.showOnAllDisplays] ? nil : windows.values.first }
    private var unlockTransition: AnyCancellable?
    @ObservedObject var coordinator = AnotchupViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private let lifecycleNotifications = NotchNotificationSubscriptions()
    private var isScreenLocked: Bool = false
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        goalStore.stopMonitoringCountdown()
        goalStore.onCountdownFinished = nil
        unlockTransition = nil
        displays.stop()
        lifecycleNotifications.stop()
        MusicManager.shared.destroy()
        CalendarManager.shared.stop()
        WebcamManager.shared.shutdown()
        ShelfStateViewModel.shared.stop()
        SharingStateManager.shared.stop()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stop()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        unlockTransition = nil
        coordinator.cancelPreviews()
        displays.cancelAll()
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        unlockTransition = nil
        coordinator.cancelPreviews()
        displays.cancelAll()
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? AnotchupSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? AnotchupSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Cancel on relock or teardown; never disable a newly locked window.
        unlockTransition = TaskNotchDelayScheduler().schedule(after: .milliseconds(150)) { [weak self] in
            guard let self, !self.isScreenLocked, !self.displays.stopped else { return }
            self.windows.values.forEach { ($0 as? AnotchupSkyLightWindow)?.disableSkyLight() }
            self.unlockTransition = nil
        }
    }

    private func cleanupWindows() {
        unlockTransition = nil
        displays.removeAll()
        cleanupDragDetectors()
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection], !displays.resources.isEmpty,
              !isScreenLocked || Defaults[.showOnLockScreen] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID, displays.resources[uuid] != nil else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        guard let model = viewModels[uuid] else { return }
        model.open()
        coordinator.currentView = .shelf
    }

    private func createAnotchupWindow(for screen: NSScreen, with viewModel: AnotchupViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = AnotchupSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        window.goalViewModel = viewModel
        
        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
                .environmentObject(goalStore)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        window.setFrameOrigin(NotchGeometry.origin(screen: screen.frame, window: window.frame.size))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        goalStore.onCountdownFinished = {
            OneGoalSoundPlayer.shared.playSelectedSound()
        }
        goalStore.startMonitoringCountdown()

        lifecycleNotifications.observe(NSApplication.didChangeScreenParametersNotification, center: .default) { [weak self] in
            self?.screenConfigurationDidChange()
        }
        lifecycleNotifications.observe(.selectedScreenChanged, center: .default) { [weak self] in
            self?.adjustWindowPosition(changeAlpha: true)
            self?.setupDragDetectors()
        }
        lifecycleNotifications.observe(.notchHeightChanged, center: .default) { [weak self] in
            self?.adjustWindowPosition()
            self?.setupDragDetectors()
        }
        lifecycleNotifications.observe(.automaticallySwitchDisplayChanged, center: .default) { [weak self] in
            guard let self else { return }
            self.window?.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
        }
        lifecycleNotifications.observe(.showOnAllDisplaysChanged, center: .default) { [weak self] in
            self?.adjustWindowPosition(changeAlpha: true)
            self?.setupDragDetectors()
        }
        lifecycleNotifications.observe(.expandedDragDetectionChanged, center: .default) { [weak self] in
            self?.setupDragDetectors()
        }
        let locked = Notification.Name("com.apple.screenIsLocked")
        let unlocked = Notification.Name("com.apple.screenIsUnlocked")
        lifecycleNotifications.observe(locked, center: DistributedNotificationCenter.default()) { [weak self] in
            self?.onScreenLocked(Notification(name: locked))
        }
        lifecycleNotifications.observe(unlocked, center: DistributedNotificationCenter.default()) { [weak self] in
            self?.onScreenUnlocked(Notification(name: unlocked))
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                let id = Defaults[.showOnAllDisplays]
                    ? NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.displayUUID
                    : self.viewModels.keys.first
                guard let id, let viewModel = self.viewModels[id],
                      !self.isScreenLocked || Defaults[.showOnLockScreen] else { return }
                viewModel.toggleFromShortcut()
            }
        }

        adjustWindowPosition(changeAlpha: true)

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        previousScreens = NSScreen.screens
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "welcome", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            adjustWindowPosition()
            setupDragDetectors()
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        let screens = Dictionary(NSScreen.screens.compactMap { screen in
            screen.displayUUID.map { ($0, screen) }
        }, uniquingKeysWith: { first, _ in first })
        let preferred = coordinator.preferredScreenUUID.flatMap { screens[$0]?.displayUUID }
        let selected = preferred ?? (Defaults[.automaticallySwitchDisplay] ? NSScreen.main?.displayUUID : nil)
        if let selected { coordinator.selectedScreenUUID = selected }
        let desired = NotchDisplayLifecycle<DisplayResource>.desiredIDs(
            available: Set(screens.keys), selected: selected, allDisplays: Defaults[.showOnAllDisplays],
            locked: isScreenLocked, showOnLockScreen: Defaults[.showOnLockScreen])
        displays.reconcile(ids: desired, make: { id in
            let model = AnotchupViewModel(screenUUID: id, scheduler: TaskNotchDelayScheduler())
            let window = createAnotchupWindow(for: screens[id]!, with: model)
            let observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification, object: window, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.setupDragDetectors() } }
            return DisplayResource(window: window, model: model, observer: observer)
        }, update: { id, resource in
            positionWindow(resource.window, on: screens[id]!, changeAlpha: changeAlpha)
            if resource.model.notchState == .closed { resource.model.close() }
        })
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
