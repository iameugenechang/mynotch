import Foundation
import XCTest
import WorkingOn
import WorkingOnAdapters

final class OneGoalEditorSessionTests: XCTestCase {
    func testDraftLifecycleAndFocusRequests() async {
        await Self.withStores { store, _, _ in
            store.save(text: "Saved")
            let editor = OneGoalEditorSession(store: store)
            editor.requestFocus(.goal)
            XCTAssertNil(editor.requestedFocus, "closed sessions reject late focus requests")
            editor.begin()
            XCTAssertEqual(editor.draft, "Saved")
            XCTAssertEqual(editor.duration, 1500)
            editor.setDraft("Unsaved")
            editor.requestFocus(.goal)
            editor.begin()
            XCTAssertEqual(editor.draft, "Unsaved", "repeat appearance cannot erase a live draft")
            XCTAssertEqual(editor.requestedFocus, .goal)
            editor.end()
            XCTAssertFalse(editor.isOpen)
            XCTAssertEqual(editor.draft, "")
            XCTAssertNil(editor.requestedFocus)
            XCTAssertEqual(store.goal.text, "Saved")
            editor.requestFocus(.seconds)
            editor.setDraft("Late edit")
            editor.save()
            editor.complete()
            editor.startCountdown()
            XCTAssertNil(editor.requestedFocus)
            XCTAssertEqual(store.goal.text, "Saved", "closed-session commands have no effects")
            editor.begin()
            XCTAssertEqual(editor.draft, "Saved")
        }
    }

    func testSaveNormalizesAndBlankSaveClearsTimer() async {
        await Self.withStores { store, _, _ in
            let editor = OneGoalEditorSession(store: store)
            editor.begin()
            editor.setDraft("  Ship it  ")
            editor.save()
            XCTAssertEqual(store.goal.text, "Ship it")
            XCTAssertFalse(editor.isOpen)
            store.startCountdown(seconds: 60)
            editor.begin()
            editor.setDraft(" \n ")
            editor.save()
            XCTAssertEqual(store.goal, OneGoal())
        }
    }

    func testStartingTimerCommitsDraftAndSurvivesCancellation() async {
        await Self.withStores { store, scheduler, _ in
            store.startMonitoringCountdown()
            defer { store.stopMonitoringCountdown() }
            let editor = OneGoalEditorSession(store: store)
            editor.begin()
            editor.setDraft("  Committed by timer  ")
            editor.setMinutes("1")
            editor.setSeconds("05")
            editor.editCustomTime()
            XCTAssertEqual(editor.requestedFocus, .minutes)
            XCTAssertEqual(editor.timerAction, .apply)
            editor.handleTimerAction()
            XCTAssertEqual(store.goal.text, "Committed by timer")
            XCTAssertEqual(store.goal.countdown?.duration, 65)
            XCTAssertEqual(editor.timerAction, .pause)
            XCTAssertFalse(editor.editingTime)
            XCTAssertNil(editor.requestedFocus)
            XCTAssertEqual(scheduler.activeCount, 1)
            editor.setDraft("Discard this later edit")
            editor.end()
            XCTAssertEqual(store.goal.text, "Committed by timer")
            XCTAssertEqual(store.goal.countdown?.duration, 65)
            XCTAssertEqual(scheduler.activeCount, 1, "closing an editor does not stop the app monitor")
        }
    }

    func testInvalidDurationOrBlankDraftCannotStartTimer() async {
        await Self.withStores { store, _, _ in
            store.save(text: "Saved")
            let editor = OneGoalEditorSession(store: store)
            editor.begin()
            editor.setDraft("Uncommitted")
            for (minutes, seconds) in [("0", "00"), ("1", "60"), ("1440", "01"), ("oops", "0")] {
                editor.setMinutes(minutes)
                editor.setSeconds(seconds)
                XCTAssertFalse(editor.canStartCountdown)
                editor.startCountdown()
                XCTAssertEqual(store.goal.text, "Saved")
                XCTAssertNil(store.goal.countdown)
            }
            editor.setMinutes("1")
            editor.setSeconds("00")
            editor.setDraft(" \n ")
            XCTAssertFalse(editor.canStartCountdown)
            editor.startCountdown()
            XCTAssertEqual(store.goal.text, "Saved")
            XCTAssertNil(store.goal.countdown)
        }
    }

    func testPauseResumeAndRestartDoNotCommitDraft() async {
        await Self.withStores { store, _, clock in
            store.save(text: "Saved")
            store.startCountdown(seconds: 90)
            let editor = OneGoalEditorSession(store: store)
            editor.begin()
            editor.setDraft("Unsaved")
            clock.now.addTimeInterval(10)
            editor.handleTimerAction()
            XCTAssertTrue(store.goal.countdown?.isPaused == true)
            XCTAssertEqual(store.goal.countdown?.pausedRemaining, 80)
            XCTAssertEqual(editor.timerAction, .resume)
            clock.now.addTimeInterval(30)
            editor.handleTimerAction()
            XCTAssertFalse(store.goal.countdown?.isPaused ?? true)
            XCTAssertEqual(store.goal.countdown?.deadline, clock.now.addingTimeInterval(80))
            editor.editCustomTime()
            editor.setMinutes("5")
            editor.restartCountdown()
            XCTAssertEqual(editor.minutes, "1")
            XCTAssertEqual(editor.seconds, "30")
            XCTAssertFalse(editor.editingTime)
            XCTAssertNil(editor.requestedFocus)
            XCTAssertEqual(store.goal.countdown?.deadline, clock.now.addingTimeInterval(90))
            editor.end()
            XCTAssertEqual(store.goal.text, "Saved")
        }
    }

    func testDurationCancelVersusClearAndPresets() async {
        await Self.withStores { store, _, _ in
            store.save(text: "Saved")
            let editor = OneGoalEditorSession(store: store)
            editor.begin()
            editor.selectPreset(minutes: 15)
            XCTAssertEqual(editor.duration, 900)
            XCTAssertNil(store.goal.countdown, "a preset only chooses fields before the first start")
            editor.handleTimerAction()
            let original = store.goal.countdown
            editor.editCustomTime()
            editor.setMinutes("2")
            editor.editCustomTime()
            XCTAssertEqual(editor.minutes, "2", "refocusing custom time preserves edits")
            editor.cancelDurationOrClearCountdown()
            XCTAssertEqual(editor.duration, 900)
            XCTAssertEqual(store.goal.countdown, original)
            editor.setDraft("Preset commits this")
            editor.selectPreset(minutes: 50)
            XCTAssertEqual(store.goal.text, "Preset commits this")
            XCTAssertEqual(store.goal.countdown?.duration, 3000)
            editor.setDraft("Clear must not commit this")
            editor.cancelDurationOrClearCountdown()
            XCTAssertNil(store.goal.countdown)
            XCTAssertEqual(store.goal.text, "Preset commits this")
        }
    }

    func testApplyingCustomDurationReplacesTimerAndCommitsDraft() async {
        await Self.withStores { store, scheduler, clock in
            store.save(text: "Saved")
            store.startMonitoringCountdown()
            defer { store.stopMonitoringCountdown() }
            store.startCountdown(seconds: 60)
            let editor = OneGoalEditorSession(store: store)
            editor.begin()
            editor.setDraft("Updated by apply")
            editor.editCustomTime()
            editor.setMinutes("0")
            editor.setSeconds("07")
            clock.now.addTimeInterval(2)
            editor.handleTimerAction()
            XCTAssertEqual(store.goal.text, "Updated by apply")
            XCTAssertEqual(store.goal.countdown?.duration, 7)
            XCTAssertEqual(store.goal.countdown?.deadline, clock.now.addingTimeInterval(7))
            XCTAssertTrue(editor.customDurationSelected)
            XCTAssertFalse(editor.editingTime)
            XCTAssertNil(editor.requestedFocus)
            XCTAssertEqual(scheduler.activeCount, 1)
            editor.end()
            XCTAssertEqual(store.goal.countdown?.duration, 7)
        }
    }

    func testTwoEditorsShareCommittedStateButNotDraftsOrFocus() async {
        await Self.withStores { store, scheduler, clock in
            store.save(text: "Shared")
            store.startMonitoringCountdown()
            defer { store.stopMonitoringCountdown() }
            let first = OneGoalEditorSession(store: store)
            let second = OneGoalEditorSession(store: store)
            first.begin()
            second.begin()
            first.setDraft("First draft")
            second.setDraft("Second draft")
            first.requestFocus(.goal)
            second.editCustomTime()
            XCTAssertEqual(first.requestedFocus, .goal)
            XCTAssertEqual(second.requestedFocus, .minutes)
            first.setMinutes("0")
            first.setSeconds("10")
            first.startCountdown()
            XCTAssertEqual(scheduler.activeCount, 1, "editors do not create their own monitors")
            XCTAssertEqual(second.draft, "Second draft", "committed changes do not overwrite another draft")
            second.cancelDurationOrClearCountdown()
            XCTAssertEqual(second.duration, 10, "cancel reloads the current shared duration")
            XCTAssertEqual(second.timerAction, .pause)
            clock.now.addTimeInterval(2)
            second.handleTimerAction()
            XCTAssertEqual(first.timerAction, .resume, "both sessions read the same committed timer")
            XCTAssertEqual(scheduler.activeCount, 0)
            first.end()
            XCTAssertTrue(second.isOpen)
            second.handleTimerAction()
            XCTAssertEqual(scheduler.activeCount, 1)
            second.save()
            XCTAssertEqual(store.goal.text, "Second draft", "explicit saves are last-writer-wins")
            first.begin()
            XCTAssertEqual(first.draft, "Second draft")
        }
    }

    func testCompletionAndEditorTeardownLeaveAppMonitorOwnedByStore() async {
        await Self.withStores { store, scheduler, clock in
            store.save(text: "Saved")
            store.startMonitoringCountdown()
            defer { store.stopMonitoringCountdown() }
            var completions = 0
            store.onCountdownFinished = { completions += 1 }
            store.startCountdown(seconds: 5)
            var editor: OneGoalEditorSession? = OneGoalEditorSession(store: store)
            let releasedEditor = { [weak editor] in editor }
            editor?.begin()
            editor = nil
            XCTAssertNil(releasedEditor())
            XCTAssertEqual(scheduler.activeCount, 1)
            clock.now.addTimeInterval(6)
            scheduler.tick()
            XCTAssertEqual(completions, 1)
            let reopened = OneGoalEditorSession(store: store)
            reopened.begin()
            XCTAssertEqual(reopened.timerAction, .restart)
            reopened.setDraft("Don't commit on restart")
            reopened.handleTimerAction()
            XCTAssertEqual(store.goal.text, "Saved")
            XCTAssertEqual(scheduler.activeCount, 1)
            reopened.complete()
            XCTAssertFalse(reopened.isOpen)
            XCTAssertEqual(store.goal, OneGoal())
            XCTAssertEqual(scheduler.activeCount, 0)
        }
    }

    @MainActor
    private final class Clock { var now = Date(timeIntervalSince1970: 10_000) }

    /// The same editor/store composition runs against both persistence implementations.
    @MainActor
    private static func withStores(_ body: @MainActor (OneGoalStore, ManualCountdownScheduler, Clock) -> Void) {
        let suite = "anotchup.editor-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for persistence in [MemoryGoalPersistence(), UserDefaultsOneGoalPersistence(defaults: defaults)] as [any OneGoalPersistence] {
            let clock = Clock()
            let scheduler = ManualCountdownScheduler()
            let store = OneGoalStore(persistence: persistence, scheduler: scheduler, clock: { clock.now })
            body(store, scheduler, clock)
            let restored = OneGoalStore(persistence: persistence, scheduler: scheduler, clock: { clock.now })
            XCTAssertEqual(restored.goal, store.goal, "reconstruction reads committed state, not editor drafts")
        }
    }
}
