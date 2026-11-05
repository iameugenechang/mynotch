//
//  AnotchupViewModel.swift
//  anotchup
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import NotchShell
import NotchShellAdapters
import SwiftUI

@MainActor
class AnotchupViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator: AnotchupViewCoordinator
    @ObservedObject var detector: FullscreenMediaDetector
    private let dependencies: NotchViewDependencies

    let animationLibrary: AnotchupAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed
    let interactions: NotchInteractionLifetime
    let displayLifetimeID = UUID()

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false
    @Published var isGoalEditorActive = false {
        didSet { coordinator.navigation.requestEditor(isGoalEditorActive, on: displayLifetimeID) }
    }

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    @Published var isCameraExpanded: Bool = false
    
    // Subscription and scheduler tokens also cancel on release. Explicit removal
    // invalidates the owner so retained native callbacks cannot restart its work.
    func destroy() {
        interactions.invalidate()
        coordinator.navigation.remove(displayLifetimeID)
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    convenience init(screenUUID: String? = nil) {
        self.init(screenUUID: screenUUID, scheduler: TaskNotchDelayScheduler())
    }

    convenience init(screenUUID: String? = nil, scheduler: any NotchDelayScheduling) {
        self.init(screenUUID: screenUUID, scheduler: scheduler, dependencies: makeAppNotchDependencies())
    }

    init(screenUUID: String? = nil, scheduler: any NotchDelayScheduling,
         dependencies: NotchViewDependencies) {
        self.dependencies = dependencies
        coordinator = dependencies.coordinator
        detector = dependencies.detector
        interactions = NotchInteractionLifetime(scheduler: scheduler)
        animation = animationLibrary.animation

        super.init()
        coordinator.navigation.register(displayLifetimeID)
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .sink { [weak self] targeting in self?.anyDropZoneTargeting = targeting }
            .store(in: &cancellables)
        
        setupDetectorObserver()
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        return NotchGeometry.closedHeight(height: closedNotchSize.height, hide: hideOnClosed,
                                          hasCutout: (currentScreen?.safeAreaInsets.top ?? 0) > 0)
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        return NotchGeometry.chinHeight(menuBar: currentScreen.frame.maxY - currentScreen.visibleFrame.maxY,
                                        closed: effectiveClosedNotchHeight, hiddenTitleBar: Defaults[.hideTitleBar],
                                        isOpen: notchState == .open)
    }

    func toggleCameraPreview() { dependencies.toggleCamera(self) }
    
    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            return NotchGeometry.contains(position, screen: frame, notch: notchSize)
        }
        
        return false
    }

    func cancelDelayedInteractions() {
        interactions.cancelAll()
    }

    private var closeInteractionState: NotchInteractionState {
        NotchInteractionState(
            isOpen: notchState == .open,
            isSharing: dependencies.isSharing(),
            isEditorActive: isGoalEditorActive
        )
    }

    func toggleFromShortcut() {
        cancelDelayedInteractions()
        guard notchState == .closed else {
            close()
            return
        }
        open()
        interactions.schedule(.shortcutClose, after: .seconds(3), state: { [weak self] in
            self?.closeInteractionState ?? NotchInteractionState(isOpen: false)
        }, apply: { [weak self] effect in
            if effect == .close { self?.close() }
        })
    }

    func open() {
        cancelDelayedInteractions()
        self.notchSize = openNotchSize
        self.notchState = .open
        
        // Force music information update when notch is opened
        dependencies.refreshMedia()
    }

    func openGoalEditor() {
        isGoalEditorActive = true
        coordinator.currentView = .goal
        open()
    }

    func close(resetSelectedTab: Bool = true) {
        // Text entry must survive hover exits and delayed auto-close tasks.
        guard closeInteractionState.canClose else { return }
        cancelDelayedInteractions()
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

        coordinator.navigation.close(
            resetSelection: resetSelectedTab,
            shelfHasItems: dependencies.shelfHasItems(),
            opensShelf: Defaults[.openShelfByDefault],
            keepsLastTab: coordinator.openLastTabByDefault
        )
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
