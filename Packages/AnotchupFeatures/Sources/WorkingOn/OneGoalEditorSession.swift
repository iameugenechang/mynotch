import Combine
import Foundation

/// One transient editor over the app-owned store. Opening an editor never starts a monitor.
/// Observe the store as well as this session when rendering committed countdown state.
@MainActor
public final class OneGoalEditorSession: ObservableObject {
    public enum Field: Hashable { case goal, minutes, seconds }
    public enum TimerAction { case start, apply, restart, resume, pause }

    @Published public private(set) var draft = ""
    @Published public private(set) var minutes = "25"
    @Published public private(set) var seconds = "00"
    @Published public private(set) var editingTime = false
    @Published public private(set) var requestedFocus: Field?
    @Published public private(set) var isOpen = false

    private let store: OneGoalStore

    public init(store: OneGoalStore) { self.store = store }

    public var duration: Int? {
        OneGoal.Countdown.parseDuration(minutes: minutes, seconds: seconds)
    }

    public var settingTime: Bool { editingTime || store.goal.countdown == nil }
    public var canStartCountdown: Bool { duration != nil && !OneGoal.normalized(draft).isEmpty }

    public var customDurationSelected: Bool {
        if editingTime { return true }
        let total = store.goal.countdown.map { Int($0.duration) } ?? duration
        return total.map { ![900, 1500, 3000].contains($0) } ?? false
    }

    public var timerAction: TimerAction {
        if settingTime { return editingTime ? .apply : .start }
        if store.goal.countdown?.isFinished == true { return .restart }
        return store.goal.countdown?.isPaused == true ? .resume : .pause
    }

    /// Repeated appearance notifications must not overwrite a live draft.
    public func begin() {
        guard !isOpen else { return }
        draft = store.goal.text
        if let countdown = store.goal.countdown { setDurationFields(countdown.duration) }
        isOpen = true
    }

    /// Cancel/disappear discards only local edits, never committed timer actions.
    public func end() {
        isOpen = false
        requestedFocus = nil
        draft = ""
        editingTime = false
    }

    public func setDraft(_ value: String) {
        guard isOpen else { return }
        draft = value
    }

    public func setMinutes(_ value: String) {
        guard isOpen else { return }
        minutes = value
    }

    public func setSeconds(_ value: String) {
        guard isOpen else { return }
        seconds = value
    }

    /// This is intent only. Native focus and window activation stay with the view.
    public func requestFocus(_ field: Field?) {
        guard isOpen else { return }
        requestedFocus = field
    }

    public func save() {
        guard isOpen else { return }
        store.save(text: draft)
        end()
    }

    public func complete() {
        guard isOpen else { return }
        store.complete()
        end()
    }

    public func editCustomTime() {
        guard isOpen else { return }
        if !editingTime, let countdown = store.goal.countdown {
            setDurationFields(countdown.duration)
        }
        editingTime = true
        requestedFocus = .minutes
    }

    public func selectPreset(minutes value: Int) {
        guard isOpen, [15, 25, 50].contains(value) else { return }
        minutes = String(value)
        seconds = "00"
        if store.goal.countdown != nil { startCountdown() }
    }

    public func handleTimerAction() {
        guard isOpen else { return }
        switch timerAction {
        case .start, .apply: startCountdown()
        case .restart: store.restartCountdown()
        case .resume: store.resumeCountdown()
        case .pause: store.pauseCountdown()
        }
    }

    /// Starting/applying a duration also commits the draft. Pause/resume/restart do not.
    public func startCountdown() {
        guard isOpen, let duration, !OneGoal.normalized(draft).isEmpty else { return }
        store.save(text: draft)
        store.startCountdown(seconds: duration)
        editingTime = false
        requestedFocus = nil
    }

    public func restartCountdown() {
        guard isOpen else { return }
        store.restartCountdown()
        if let countdown = store.goal.countdown { setDurationFields(countdown.duration) }
        editingTime = false
        requestedFocus = nil
    }

    public func cancelDurationOrClearCountdown() {
        guard isOpen else { return }
        if editingTime, let countdown = store.goal.countdown {
            setDurationFields(countdown.duration)
        } else {
            store.clearCountdown()
        }
        editingTime = false
        requestedFocus = nil
    }

    private func setDurationFields(_ value: TimeInterval) {
        let total = Int(value)
        minutes = String(total / 60)
        seconds = String(format: "%02d", total % 60)
    }
}
