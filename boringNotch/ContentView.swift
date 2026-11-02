//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject private var goalStore = OneGoalStore.shared
    @Default(.oneGoalFontSize) private var oneGoalFontSize
    @Default(.oneGoalTextPadding) private var oneGoalTextPadding
    @Default(.oneGoalTimerStyle) private var oneGoalTimerStyle
    @Default(.oneGoalVerticalOffset) private var oneGoalVerticalOffset
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var isHoveringGoalControl = false
    @State private var isPointerInsideNotch = false
    @State private var notchContentSize = CGSize.zero
    @State private var collapsedTimerWidth: CGFloat = 0
    @State private var timerTracksClosedWidth = true
    @State private var timerResizeTask: Task<Void, Never>?
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.keepMediaVisibleWhenPaused) private var keepMediaVisibleWhenPaused

    @Default(.showNotHumanFace) var showNotHumanFace

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    // Expanded controls still respect the display's camera reservation.
    private var goalHeaderHeight: CGFloat {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        return max(24, vm.effectiveClosedNotchHeight, screen?.safeAreaInsets.top ?? 0)
    }

    // Use the menu bar as the caption baseline. Vertical offset can extend
    // the shared silhouette below the camera cutout.
    private var goalMenuBarHeight: CGFloat {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        guard let screen else { return NSStatusBar.system.thickness }
        let visibleInset = screen.frame.maxY - screen.visibleFrame.maxY
        if visibleInset > 0 { return visibleInset }
        // The menu bar can be hidden in fullscreen; keep a stable compact band.
        return max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
    }

    private var oneGoalBarHeight: CGFloat {
        oneGoalCaptionHeight(fontSize: oneGoalFontSize, padding: oneGoalTextPadding)
    }

    private var showsMediaPlayer: Bool {
        MediaVisibilityPolicy.shouldShowPlayer(isPlaying: musicManager.isPlaying, isIdle: musicManager.isPlayerIdle,
            keepWhilePaused: keepMediaVisibleWhenPaused, hasTrack: musicManager.hasCurrentTrack)
    }

    private var showsGoal: Bool {
        !coordinator.helloAnimationRunning && !goalStore.goal.text.isEmpty
    }

    private var showsNotchPreview: Bool {
        vm.notchState == .closed && (coordinator.sneakPeek.show || coordinator.expandingView.show)
    }

    private var goalLayout: OneGoalLayout {
        OneGoalLayout(menuBarHeight: goalMenuBarHeight, captionHeight: oneGoalBarHeight,
                      hitPadding: goalCaptionHitPadding, verticalOffset: oneGoalVerticalOffset)
    }

    private var goalExtensionHeight: CGFloat {
        guard showsGoal else { return 0 }
        let bodyHeight = vm.notchState == .open ? vm.notchSize.height : max(notchContentSize.height, goalMenuBarHeight)
        return goalLayout.extensionHeight(contentHeight: bodyHeight, isPreview: showsNotchPreview)
    }

    private var goalTimerWidth: CGFloat {
        collapsedTimerWidth > 0 ? collapsedTimerWidth
            : OneGoalLayout.timerWidth(notchWidth: vm.closedNotchSize.width,
                                      curveInset: cornerRadiusInsets.closed.top + cornerRadiusInsets.closed.bottom)
    }

    private func updateCollapsedTimerWidth() {
        collapsedTimerWidth = OneGoalLayout.timerWidth(notchWidth: notchContentSize.width,
            curveInset: cornerRadiusInsets.closed.top + cornerRadiusInsets.closed.bottom)
    }

    private func refreshTimerTracking() {
        timerResizeTask?.cancel()
        timerTracksClosedWidth = false
        guard vm.notchState == .closed, !showsNotchPreview else { return }
        // Resume only after both expansion and temporary previews have settled.
        timerResizeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, vm.notchState == .closed, !showsNotchPreview else { return }
            updateCollapsedTimerWidth()
            timerTracksClosedWidth = true
        }
    }

    private var goalCurvePadding: CGFloat {
        topCornerRadius + ((vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom)
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil, alignment: .top)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                        notchContentSize = size
                        if vm.notchState == .closed && timerTracksClosedWidth && !showsNotchPreview {
                            updateCollapsedTimerWidth()
                        }
                    }
                    .padding(.bottom, goalExtensionHeight)
                    .background(.black)
                    .overlay(alignment: .top) {
                        if showsGoal {
                            GeometryReader { geometry in
                                OneGoalLabel(
                                    width: geometry.size.width,
                                    horizontalPadding: goalCurvePadding,
                                    timerWidth: goalTimerWidth,
                                    action: openGoalEditor
                                )
                                .onHover(perform: handleGoalHover)
                                .contextMenu { notchContextMenu }
                                .offset(y: goalLayout.captionOrigin(bodyHeight: geometry.size.height))
                            }
                        }
                    }
                    // Clip body, goal, and timer together, giving the entire
                    // silhouette one shared width and outer curve.
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                
                mainLayout
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: coordinator.currentView) { _, newView in
                        if newView != .goal { vm.isGoalEditorActive = false }
                    }
                    .onChange(of: showsNotchPreview) { _, _ in
                        refreshTimerTracking()
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        refreshTimerTracking()
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu { notchContextMenu }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("notch-body")
            }

        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: vm.notchState == .closed ? 0 : 8) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    Group {
                        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                        {
                            HStack(spacing: 0) {
                                HStack {
                                    Text(batteryModel.statusText)
                                        .font(.subheadline)
                                        .foregroundStyle(.white)
                                }

                                Rectangle()
                                    .fill(.black)
                                    .frame(width: vm.closedNotchSize.width + 10)

                                HStack {
                                    BoringBatteryView(
                                        batteryWidth: 30,
                                        isCharging: batteryModel.isCharging,
                                        isInLowPowerMode: batteryModel.isInLowPowerMode,
                                        isPluggedIn: batteryModel.isPluggedIn,
                                        levelBattery: batteryModel.levelBattery,
                                        isForNotification: true
                                    )
                                }
                                .frame(width: 76, alignment: .trailing)
                            }
                            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                        } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                            InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                                .transition(.opacity)
                        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && showsMediaPlayer && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                            MusicLiveActivity()
                                .frame(alignment: .center)
                        } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed {
                            BoringFaceAnimation()
                        } else if vm.notchState == .open {
                            BoringHeader()
                                .frame(height: max(24, vm.effectiveClosedNotchHeight))
                                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                        } else {
                            Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                        }
                    }
                    .frame(height: vm.notchState == .closed ? goalMenuBarHeight : nil)
                    .frame(minHeight: vm.notchState == .open ? goalHeaderHeight : nil)
                    .clipped()
                    .accessibilityElement(children: .contain)

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .shelf:
                        ShelfView()
                    case .goal:
                        OneGoalView()
                    }
                }
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? min(380, windowSize.width - 2 * max(0, vm.effectiveClosedNotchHeight - 12) - 16 - 2 * cornerRadiusInsets.closed.bottom)
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if oneGoalTimerStyle == .visualizerRing && goalStore.goal.countdown != nil {
                    OneGoalRingVisualizer(action: openGoalEditor)
                        .onHover(perform: handleGoalHover)
                } else if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var notchContextMenu: some View {
        Button("Working on", action: openGoalEditor)
        if let countdown = goalStore.goal.countdown {
            if !countdown.isFinished {
                Button(countdown.isPaused ? "Resume timer" : "Pause timer") {
                    if countdown.isPaused {
                        goalStore.resumeCountdown()
                    } else {
                        goalStore.pauseCountdown()
                    }
                }
            }
            Button("Restart timer") { goalStore.restartCountdown() }
            Button("Clear timer", action: goalStore.clearCountdown)
        }
        Divider()
        Button("Settings") {
            DispatchQueue.main.async {
                SettingsWindowController.shared.showWindow()
            }
        }
        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
        Divider()
        Button("Quit mynotch") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func openGoalEditor() {
        hoverTask?.cancel()
        vm.openGoalEditor()
    }

    private func handleGoalHover(_ hovering: Bool) {
        isHoveringGoalControl = hovering
        if hovering {
            hoverTask?.cancel()
        } else {
            handleHover(isPointerInsideNotch)
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        isPointerInsideNotch = hovering
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !isHoveringGoalControl,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          !self.isHoveringGoalControl,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open,
              coordinator.currentView == .goal || !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose {
                hoverTask?.cancel()
                gestureProgress = .zero
                // A deliberate close gesture is equivalent to Cancel, not a
                // hover exit. Release the editor's automatic-close protection.
                vm.isGoalEditorActive = false
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
