import Defaults
import SwiftUI
import WorkingOn

private func oneGoalPlayerTint(_ color: NSColor, enabled: Bool) -> Color {
    enabled ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
}

struct OneGoalLabel: View {
    @EnvironmentObject private var store: OneGoalStore
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.playerColorTinting) private var playerColorTinting
    @Default(.oneGoalFontSize) private var fontSize
    @Default(.oneGoalTextPadding) private var textPadding
    @Default(.oneGoalTimerStyle) private var timerStyle
    @Default(.oneGoalTimerPosition) private var timerPosition
    let width: CGFloat
    let horizontalPadding: CGFloat
    let timerWidth: CGFloat
    var action: () -> Void

    var body: some View {
        if !store.goal.text.isEmpty {
            if let countdown = store.goal.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    caption(
                        fraction: countdown.fractionRemaining(at: context.date),
                        remaining: countdown.statusText(at: context.date)
                    )
                }
            } else {
                caption(fraction: nil, remaining: nil)
            }
        }
    }

    private var textColor: Color {
        oneGoalPlayerTint(musicManager.avgColor, enabled: playerColorTinting)
    }

    private var barHeight: CGFloat {
        oneGoalCaptionHeight(fontSize: fontSize, padding: textPadding)
    }

    private func caption(fraction: Double?, remaining: String?) -> some View {
        Button(action: action) {
            Text(store.goal.text)
                .font(.system(size: fontSize))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, textPadding)
                .padding(timerPosition == .top ? .top : .bottom, 1)
                .frame(width: max(0, width))
                .frame(height: barHeight)
                .overlay(alignment: timerPosition == .top ? .top : .bottom) {
                    if let fraction, timerStyle == .underline {
                        Rectangle()
                            .fill(textColor)
                            .frame(width: max(0, timerWidth) * fraction, height: 1)
                            .frame(width: max(0, timerWidth), alignment: .leading)
                        .accessibilityHidden(true)
                    }
                }
                .clipped()
                // Extra input area stays invisible when the bar is short.
                .padding(.top, goalCaptionHitPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(remaining.map { "\(store.goal.text) (\($0))" } ?? store.goal.text)
        .accessibilityLabel("Working on: \(store.goal.text)")
        .accessibilityHint("Edit what you're working on.")
        .accessibilityValue(remaining ?? "No countdown")
        .accessibilityIdentifier("working-on-label")
        .transaction { $0.disablesAnimations = true }
    }
}

struct OneGoalAppearanceSettings: View {
    @Default(.oneGoalCompletionSound) private var completionSound
    @Default(.oneGoalSoundVolume) private var soundVolume
    @Default(.oneGoalFontSize) private var fontSize
    @Default(.oneGoalTextPadding) private var textPadding
    @Default(.oneGoalVerticalOffset) private var verticalOffset
    @Default(.oneGoalTimerStyle) private var timerStyle
    @Default(.oneGoalTimerPosition) private var timerPosition

    var body: some View {
        Form {
            Section {
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $fontSize, in: 5...24, step: 1)
                            .frame(width: 180)
                        Text("\(Int(fontSize))").monospacedDigit().frame(width: 32)
                    }
                }
                LabeledContent("Text padding") {
                    HStack {
                        Slider(value: $textPadding, in: 0...12, step: 1)
                            .frame(width: 180)
                        Text("\(Int(textPadding))").monospacedDigit().frame(width: 32)
                    }
                }
                LabeledContent("Vertical offset") {
                    HStack {
                        Slider(value: $verticalOffset, in: -24...64, step: 1)
                            .frame(width: 180)
                        Text("\(Int(verticalOffset))").monospacedDigit().frame(width: 32)
                    }
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Height follows the text size automatically. Padding adds space above and below the text. Positive offset moves the collapsed caption down; expansion keeps it at the bottom.")
            }

            Section {
                Picker("Display", selection: $timerStyle) {
                    Text("Underline").tag(OneGoalTimerStyle.underline)
                    Text("Visualizer ring").tag(OneGoalTimerStyle.visualizerRing)
                }
                .pickerStyle(.segmented)
                if timerStyle == .underline {
                    Picker("Position", selection: $timerPosition) {
                        Text("Top").tag(OneGoalTimerPosition.top)
                        Text("Bottom").tag(OneGoalTimerPosition.bottom)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Countdown")
            } footer: {
                Text("Text and timer both follow Player tinting in Appearance. The ring surrounds the music visualizer when visible; the caption tooltip always shows the exact remaining time.")
            }

            Section {
                Picker("Sound", selection: $completionSound) {
                    ForEach(OneGoalCompletionSound.allCases, id: \.self) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                LabeledContent("Volume") {
                    HStack {
                        Slider(value: $soundVolume, in: 0...1, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int((soundVolume * 100).rounded()))%")
                            .monospacedDigit().frame(width: 44)
                    }
                }
                .disabled(completionSound == .silent)
                Button("Preview sound", action: OneGoalSoundPlayer.shared.playSelectedSound)
                    .disabled(completionSound == .silent || soundVolume == 0)
            } header: {
                Text("Timer finished")
            } footer: {
                Text("Plays once when the countdown reaches zero. Your text stays visible until you choose Done. Choose Silent for no sound.")
            }

            Section {
                Button("Reset layout") {
                    fontSize = 7
                    textPadding = 1
                    verticalOffset = 12
                    timerStyle = .underline
                    timerPosition = .bottom
                }
            }
        }
        .navigationTitle("Working on")
    }
}

struct OneGoalView: View {
    @EnvironmentObject private var vm: AnotchupViewModel
    @ObservedObject private var store: OneGoalStore
    @StateObject private var editor: OneGoalEditorSession
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.playerColorTinting) private var playerColorTinting
    @FocusState private var focusedField: OneGoalEditorSession.Field?

    init(store: OneGoalStore) {
        self.store = store
        _editor = StateObject(wrappedValue: OneGoalEditorSession(store: store))
    }

    private var tint: Color {
        oneGoalPlayerTint(musicManager.avgColor, enabled: playerColorTinting)
    }

    private var timerStatus: String {
        guard let countdown = store.goal.countdown else { return "Optional countdown" }
        if editor.editingTime { return "Set duration" }
        if countdown.isFinished { return "Finished" }
        return countdown.isPaused ? "Paused" : "Time remaining"
    }

    private var timerActionLabel: String {
        switch editor.timerAction {
        case .start: return "Start timer"
        case .apply: return "Set timer"
        case .restart: return "Restart timer"
        case .resume: return "Resume timer"
        case .pause: return "Pause timer"
        }
    }

    private var timerActionIcon: String {
        switch editor.timerAction {
        case .apply: return "checkmark"
        case .restart: return "arrow.clockwise"
        case .start, .resume: return "play.fill"
        case .pause: return "pause.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("What are you working on?", systemImage: "pencil")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)

                TextField("e.g. The proposal for Maya", text: Binding(get: { editor.draft }, set: editor.setDraft))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .tint(tint)
                    .focused($focusedField, equals: .goal)
                    .onSubmit(save)
                    .accessibilityLabel("What are you working on?")
                    .accessibilityHint("Describe what you're working on. Press Return to save.")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(focusedField == .goal ? tint.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { editor.requestFocus(.goal) }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        editor.complete()
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Clear the saved text and countdown.")
                    .disabled(store.goal.text.isEmpty && OneGoal.normalized(editor.draft).isEmpty)

                    Spacer(minLength: 0)

                    Button("Cancel", action: dismiss)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)

                    Button(action: save) {
                        Text("Save")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(tint.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            timerCard
        }
        .frame(height: 126)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneGoalInputFocus(isEditing: vm.isGoalEditorActive))
        .task {
            editor.begin()
            await Task.yield()
            guard !Task.isCancelled, editor.isOpen else { return }
            if vm.isGoalEditorActive { editor.requestFocus(.goal) }
        }
        .onChange(of: vm.isGoalEditorActive) { _, active in
            if active { editor.requestFocus(.goal) }
        }
        .onChange(of: editor.requestedFocus) { _, field in
            focusedField = field
        }
        .onChange(of: focusedField) { _, field in
            editor.requestFocus(field)
        }
        .onDisappear {
            editor.end()
            focusedField = nil
            vm.isGoalEditorActive = false
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(timerStatus)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if store.goal.countdown != nil {
                    timerIcon("arrow.counterclockwise", label: "Restart timer", action: editor.restartCountdown)
                    timerIcon("xmark", label: editor.editingTime ? "Cancel duration change" : "Clear timer",
                              action: editor.cancelDurationOrClearCountdown)
                }
            }
            .frame(height: 18)

            HStack(alignment: .center, spacing: 6) {
                timerValue
                    .font(.system(size: 27, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Button(action: editor.handleTimerAction) {
                    Image(systemName: timerActionIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                .help(timerActionLabel)
                .accessibilityLabel(timerActionLabel)
                .disabled(editor.settingTime && !editor.canStartCountdown)
            }
            .frame(height: 34)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach([15, 25, 50], id: \.self) { preset in
                    let selected = store.goal.countdown.map { $0.duration == TimeInterval(preset * 60) }
                        ?? (editor.duration == preset * 60)
                    Button {
                        editor.selectPreset(minutes: preset)
                    } label: {
                        Text("\(preset)m")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(selected ? tint : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(selected ? tint.opacity(0.13) : Color.white.opacity(0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(store.goal.countdown == nil ? "Choose \(preset) minutes" : "Restart with \(preset) minutes")
                    .disabled(store.goal.countdown != nil && OneGoal.normalized(editor.draft).isEmpty)
                }
                Button(action: editor.editCustomTime) {
                    Text("Custom")
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(editor.customDurationSelected ? tint : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(editor.customDurationSelected ? tint.opacity(0.13) : Color.white.opacity(0.04), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Enter minutes and seconds")
                .accessibilityLabel("Custom countdown duration")
            }
        }
        .padding(12)
        .frame(width: 190, height: 126)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.06), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var timerValue: some View {
        if let countdown = store.goal.countdown, !editor.editingTime {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Button(action: editor.editCustomTime) {
                    Text(countdown.remainingText(at: context.date))
                }
                .buttonStyle(.plain)
                .help("Click to change duration")
                .accessibilityLabel("Change countdown duration")
                .accessibilityValue(countdown.statusText(at: context.date))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                TextField("min", text: Binding(get: { editor.minutes }, set: editor.setMinutes))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .minutes)
                    .onSubmit(editor.startCountdown)
                    .frame(width: 60)
                    .accessibilityLabel("Countdown minutes")
                    .help("Minutes, from 0 to 1440")
                Text(":")
                    .foregroundStyle(.secondary)
                TextField("sec", text: Binding(get: { editor.seconds }, set: editor.setSeconds))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .seconds)
                    .onSubmit(editor.startCountdown)
                    .frame(width: 30)
                    .accessibilityLabel("Countdown seconds")
                    .help("Seconds, from 0 to 59")
            }
            .font(.system(size: 24, weight: .medium, design: .rounded))
            .help("Minutes : seconds. From 1 second to 24 hours.")
        }
    }

    private func timerIcon(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func save() {
        editor.save()
        dismiss()
    }

    private func dismiss() {
        editor.end()
        focusedField = nil
        vm.isGoalEditorActive = false
        vm.close()
    }
}

struct OneGoalCountdownRing: View {
    @EnvironmentObject private var store: OneGoalStore
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.playerColorTinting) private var playerColorTinting
    var action: () -> Void

    var body: some View {
        if let countdown = store.goal.countdown {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let tint = oneGoalPlayerTint(musicManager.avgColor, enabled: playerColorTinting)
                Button(action: action) {
                    ZStack {
                        Circle().stroke(tint.opacity(0.18), lineWidth: 1)
                        Circle()
                            .trim(from: 0, to: countdown.fractionRemaining(at: context.date))
                            .stroke(tint, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("\(countdown.statusText(at: context.date)). Edit what you're working on.")
                .accessibilityLabel("Edit what you're working on")
                .accessibilityValue(countdown.statusText(at: context.date))
            }
            .transaction { $0.disablesAnimations = true }
        }
    }
}

/// Keep the same small visualizer and ring available in the expanded header.
struct OneGoalRingVisualizer: View {
    @EnvironmentObject private var store: OneGoalStore
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.oneGoalTimerStyle) private var timerStyle
    @Default(.coloredSpectrogram) private var coloredSpectrogram
    var action: () -> Void

    var body: some View {
        if timerStyle == .visualizerRing && store.goal.countdown != nil {
            ZStack(alignment: .center) {
                Rectangle()
                    .fill((coloredSpectrogram ? Color(nsColor: musicManager.avgColor) : .gray).gradient)
                    .frame(width: 10, height: 10)
                    .mask {
                        AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                            .frame(width: 10, height: 10)
                    }
                OneGoalCountdownRing(action: action)
            }
            .frame(width: 20, height: 20)
        }
    }
}

/// The notch normally cannot become key. Request input focus only for this editor.
private struct OneGoalInputFocus: NSViewRepresentable {
    var isEditing: Bool

    func makeNSView(context: Context) -> FocusView { FocusView() }

    func updateNSView(_ nsView: FocusView, context: Context) {
        nsView.isEditing = isEditing
        nsView.requestFocus()
    }

    static func dismantleNSView(_ nsView: FocusView, coordinator: ()) {
        nsView.isEditing = false
        if nsView.window?.isKeyWindow == true { nsView.window?.resignKey() }
    }

    final class FocusView: NSView {
        var isEditing = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            requestFocus()
        }

        func requestFocus() {
            guard isEditing else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEditing, let window = self.window,
                      !window.isKeyWindow else { return }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
