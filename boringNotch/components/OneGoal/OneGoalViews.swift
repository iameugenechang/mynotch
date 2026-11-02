import SwiftUI

struct OneGoalLabel: View {
    @ObservedObject private var store = OneGoalStore.shared
    let maxWidth: CGFloat
    var action: () -> Void

    var body: some View {
        if !store.goal.text.isEmpty {
            if let countdown = store.goal.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    caption(
                        fraction: countdown.fractionRemaining(at: context.date),
                        remaining: countdown.remainingText(at: context.date)
                    )
                }
            } else {
                caption(fraction: nil, remaining: nil)
            }
        }
    }

    private func caption(fraction: Double?, remaining: String?) -> some View {
        Button(action: action) {
            Text(store.goal.text)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
                .padding(.bottom, 1)
                .frame(maxWidth: max(0, maxWidth))
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: goalLabelHeight)
                .background {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 2,
                        bottomTrailingRadius: 2,
                        topTrailingRadius: 0
                    )
                    .fill(.black)
                    .padding(.top, -1) // Cover subpixel seams at the shared edge.
                }
                .overlay(alignment: .bottom) {
                    if let fraction {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.white.opacity(0.7))
                                .frame(width: geometry.size.width * fraction, height: 1)
                        }
                        .frame(height: 1)
                        .padding(.horizontal, 2)
                        .accessibilityHidden(true)
                    }
                }
                // Keep an 18pt click target without adding visible backing.
                .padding(.bottom, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(remaining.map { "\(store.goal.text) (\($0) remaining)" } ?? store.goal.text)
        .accessibilityLabel("Edit goal: \(store.goal.text)")
        .accessibilityValue(remaining.map { "\($0) remaining" } ?? "No countdown")
        .accessibilityIdentifier("one-goal-label")
        .transaction { $0.disablesAnimations = true }
    }
}

struct OneGoalView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var store = OneGoalStore.shared
    @State private var draft = ""
    @State private var minutes = "25"
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case goal, minutes }

    private var duration: Int? {
        guard let value = Int(minutes), (1...1440).contains(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What does done mean?")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("One clear outcome", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .goal)
                .onSubmit(save)
                .accessibilityLabel("Goal")

            HStack(spacing: 8) {
                Text("Countdown")
                    .foregroundStyle(.secondary)
                TextField("Minutes", text: $minutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .focused($focusedField, equals: .minutes)
                    .onSubmit(startCountdown)
                    .accessibilityLabel("Countdown minutes")
                    .help("Optional, from 1 to 1440 minutes")
                Text("min")
                    .foregroundStyle(.secondary)
                Button(store.goal.countdown == nil ? "Start" : "Restart", action: startCountdown)
                    .disabled(duration == nil || OneGoal.normalized(draft).isEmpty)

                if let countdown = store.goal.countdown {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(countdown.remainingText(at: context.date))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Button("Clear", action: store.clearCountdown)
                        .help("Remove the countdown, keeping the goal")
                }
                Spacer(minLength: 0)
            }
            .font(.caption)

            HStack {
                Button("Complete") {
                    store.complete()
                    dismiss()
                }
                .disabled(store.goal.text.isEmpty && OneGoal.normalized(draft).isEmpty)
                Spacer()
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneGoalInputFocus(isEditing: vm.isGoalEditorActive))
        .task {
            draft = store.goal.text
            if let countdown = store.goal.countdown {
                minutes = String(Int(countdown.duration / 60))
            }
            await Task.yield()
            if vm.isGoalEditorActive { focusedField = .goal }
        }
        .onChange(of: vm.isGoalEditorActive) { _, active in
            if active { focusedField = .goal }
        }
        .onDisappear {
            focusedField = nil
            draft = ""
            vm.isGoalEditorActive = false
        }
    }

    private func save() {
        store.save(text: draft)
        dismiss()
    }

    private func startCountdown() {
        guard let duration else { return }
        store.save(text: draft)
        store.startCountdown(minutes: duration)
    }

    private func dismiss() {
        focusedField = nil
        vm.isGoalEditorActive = false
        vm.close()
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
