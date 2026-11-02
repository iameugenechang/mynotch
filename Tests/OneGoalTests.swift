import Foundation

// Compiles the production model/store without launching the app or playing sounds.
@main
struct OneGoalTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
    }

    @MainActor private static var checks = 0

    @MainActor
    static func main() throws {
        try persistenceAndValidation()
        durationParsing()
        pauseResumeAndRestart()
        completionDelivery()
        completionScheduler()
        try legacySnapshots()
        layoutRules()
        pausedMediaVisibility()
        print("One Goal: \(checks) checks passed")
    }

    @MainActor
    private static func withStore(_ body: (UserDefaults, Clock, OneGoalStore) throws -> Void) rethrows {
        let suite = "mynotch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock()
        let store = OneGoalStore(defaults: defaults, clock: { clock.now })
        try body(defaults, clock, store)
    }

    @MainActor
    private static func persistenceAndValidation() throws {
        try withStore { defaults, clock, store in
            expect(store.goal == OneGoal(), "starts empty")
            store.startCountdown(seconds: 30)
            expect(store.goal.countdown == nil, "empty goal cannot start a countdown")
            store.pauseCountdown()
            store.resumeCountdown()
            store.restartCountdown()
            expect(store.goal == OneGoal(), "controls on an absent countdown are harmless")
            store.save(text: " \nSend  the\tproposal to Maya \n")
            expect(store.goal.text == "Send the proposal to Maya", "normalizes whitespace")
            expect(OneGoalStore(defaults: defaults).goal == store.goal, "saved goal survives relaunch")
            store.startCountdown(minutes: 25)
            let countdown = store.goal.countdown!
            expect(countdown.duration == 1500, "minutes API uses seconds internally")
            expect(countdown.deadline == clock.now.addingTimeInterval(1500), "uses injected wall clock")
            expect(countdown.fractionRemaining(at: clock.now) == 1, "starts full")
            expect(countdown.fractionRemaining(at: clock.now.addingTimeInterval(750)) == 0.5, "halfway fraction")
            expect(countdown.remainingText(at: clock.now.addingTimeInterval(1)) == "24:59", "formats running countdown")
            expect(countdown.remainingText(at: clock.now.addingTimeInterval(1499.5)) == "0:01", "rounds partial seconds up")
            expect(countdown.remainingText(at: clock.now.addingTimeInterval(3000)) == "0:00", "expiry clamps at zero")
            expect(countdown.statusText(at: clock.now.addingTimeInterval(3000)) == "Finished", "expiry status")
            expect(countdown.fractionRemaining(at: clock.now.addingTimeInterval(-100)) == 1, "clock rollback cannot overflow ring")
            expect(countdown.remainingText(at: clock.now.addingTimeInterval(1200)) == "5:00", "elapsed sleep time is not lost")
            store.save(text: "Send the revised proposal")
            expect(store.goal.countdown == countdown, "editing preserves countdown and deadline")
            for invalid in [-1, 0, 1441, Int.max] {
                store.startCountdown(minutes: invalid)
                expect(store.goal.countdown == countdown, "rejects invalid minutes \(invalid)")
            }
            for invalid in [-1, 0, 86_401, Int.max] {
                store.startCountdown(seconds: invalid)
                expect(store.goal.countdown == countdown, "rejects invalid seconds \(invalid)")
            }
            store.startCountdown(seconds: 450)
            expect(store.goal.countdown?.remainingText(at: clock.now) == "7:30", "custom duration keeps seconds")
            store.startCountdown(seconds: 1)
            expect(store.goal.countdown?.duration == 1, "one-second lower bound")
            store.startCountdown(seconds: 86_400)
            expect(store.goal.countdown?.duration == 86_400, "24-hour upper bound")
            store.clearCountdown()
            expect(store.goal.countdown == nil && !store.goal.text.isEmpty, "clear keeps goal")
            store.startCountdown(seconds: 30)
            store.complete()
            expect(store.goal == OneGoal(), "complete clears goal and countdown")
            expect(defaults.object(forKey: OneGoalStore.storageKey) == nil, "completion deletes snapshot")
            expect(OneGoalStore(defaults: defaults).goal == OneGoal(), "completed goal does not return")
            store.save(text: "完成报告 👩🏽‍💻\nReview\tthen send")
            expect(store.goal.text == "完成报告 👩🏽‍💻 Review then send", "Unicode is retained while whitespace is normalized")
            store.startCountdown(seconds: 30)
            store.save(text: " \n\t ")
            expect(store.goal == OneGoal(), "blank save clears text and timer")
            expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("oneGoal.") }.isEmpty, "no history keys")

            defaults.set(Data("not json".utf8), forKey: OneGoalStore.storageKey)
            expect(OneGoalStore(defaults: defaults).goal == OneGoal(), "corrupt data is safe")
            expect(defaults.object(forKey: OneGoalStore.storageKey) == nil, "corrupt snapshot is removed")
            for duration: TimeInterval in [-1, 0, 86_401] {
                let invalid = OneGoal(text: "Keep this goal", countdown: .init(duration: duration, deadline: clock.now))
                defaults.set(try JSONEncoder().encode(invalid), forKey: OneGoalStore.storageKey)
                let repaired = OneGoalStore(defaults: defaults)
                expect(repaired.goal.text == "Keep this goal" && repaired.goal.countdown == nil, "invalid duration does not discard goal")
            }
            for remaining: TimeInterval in [-1, 0, 61] {
                var paused = OneGoal.Countdown(duration: 60, deadline: clock.now)
                paused.pausedRemaining = remaining
                defaults.set(try JSONEncoder().encode(OneGoal(text: "Keep this goal", countdown: paused)), forKey: OneGoalStore.storageKey)
                expect(OneGoalStore(defaults: defaults).goal.countdown == nil, "invalid paused remainder is discarded")
            }
            let orphan = OneGoal(text: "  ", countdown: .init(duration: 60, deadline: clock.now))
            defaults.set(try JSONEncoder().encode(orphan), forKey: OneGoalStore.storageKey)
            expect(OneGoalStore(defaults: defaults).goal == OneGoal(), "orphan countdown is discarded")
        }
    }

    @MainActor
    private static func durationParsing() {
        let cases: [(String, String, Int?)] = [
            ("7", "30", 450), ("25", "00", 1500), ("", "30", 30), ("7", "", 420),
            (" 7 ", " 30\n", 450), ("0", "01", 1), ("1440", "00", 86_400),
            ("1440", "01", nil), ("0", "0", nil), ("", "", nil), ("-1", "30", nil),
            ("1", "-1", nil), ("1", "60", nil), ("1500", "0", nil), ("1.5", "0", nil),
            ("7:30", "0", nil), (String(Int.max), "0", nil), ("999999999999999999999", "0", nil)
        ]
        for (minutes, seconds, expected) in cases {
            expect(OneGoal.Countdown.parseDuration(minutes: minutes, seconds: seconds) == expected,
                   "parse minutes=\(minutes.debugDescription), seconds=\(seconds.debugDescription)")
        }
    }

    @MainActor
    private static func pauseResumeAndRestart() {
        withStore { defaults, clock, store in
            var completions = 0
            store.onCountdownFinished = { completions += 1 }
            store.startMonitoringCountdown()
            store.save(text: "Finish the proposal")
            store.startCountdown(seconds: 450)
            clock.advance(90.25)
            store.pauseCountdown()
            let paused = store.goal.countdown!
            expect(paused.isPaused, "pause sets state")
            expect(abs(paused.remaining(at: clock.now) - 359.75) < 0.001, "pause preserves fractional seconds")
            expect(paused.statusText(at: clock.now) == "6:00 paused", "paused status is explicit")
            clock.advance(86_400)
            store.refreshCountdown()
            expect(store.goal.countdown == paused, "paused time does not decay during sleep")
            expect(completions == 0, "paused timer cannot finish or sound")
            store.pauseCountdown()
            expect(store.goal.countdown == paused, "repeated pause is harmless")
            store.save(text: "Finish the revised proposal")
            expect(store.goal.countdown == paused, "editing keeps paused state")
            let reopened = OneGoalStore(defaults: defaults, clock: { clock.now })
            reopened.startMonitoringCountdown()
            expect(reopened.goal.countdown == paused, "paused remainder survives relaunch")
            reopened.resumeCountdown()
            expect(reopened.goal.countdown?.isPaused == false, "resume clears pause state")
            expect(reopened.goal.countdown?.deadline == clock.now.addingTimeInterval(359.75), "resume rebuilds deadline from frozen remainder")
            let resumed = reopened.goal.countdown!
            reopened.resumeCountdown()
            expect(reopened.goal.countdown == resumed, "repeated resume does not reset time")
            clock.advance(60)
            expect(abs(reopened.goal.countdown!.remaining(at: clock.now) - 299.75) < 0.001, "resumed countdown advances normally")
            reopened.pauseCountdown()
            reopened.restartCountdown()
            expect(reopened.goal.countdown?.duration == 450, "restart retains original custom duration")
            expect(reopened.goal.countdown?.remaining(at: clock.now) == 450, "restart begins a full duration")
            expect(reopened.goal.countdown?.isPaused == false, "restart resumes a paused timer")
            reopened.clearCountdown()
            expect(reopened.goal.text == "Finish the revised proposal", "clearing paused timer keeps goal")
        }
    }

    @MainActor
    private static func completionDelivery() {
        withStore { defaults, clock, store in
            var completions = 0
            store.onCountdownFinished = {
                let data = defaults.data(forKey: OneGoalStore.storageKey)!
                let persisted = try! JSONDecoder().decode(OneGoal.self, from: data)
                expect(persisted.countdown?.isFinished == true, "handled flag is saved before completion callback")
                completions += 1
            }
            store.startMonitoringCountdown()
            store.startMonitoringCountdown()
            store.save(text: "One active goal")
            store.startCountdown(seconds: 10)
            clock.advance(9.5)
            store.refreshCountdown()
            expect(completions == 0, "cannot sound before deadline")
            clock.advance(0.5)
            for _ in 0..<5 { store.refreshCountdown() }
            expect(completions == 1, "completion is delivered exactly once")
            expect(store.goal.countdown?.isFinished == true, "finished state retained")
            expect(store.goal.text == "One active goal", "timer expiry does not complete goal")
            store.pauseCountdown()
            expect(store.goal.countdown?.isPaused == false, "finished timer cannot be paused")
            var restoredCompletions = 0
            let restored = OneGoalStore(defaults: defaults, clock: { clock.now })
            restored.onCountdownFinished = { restoredCompletions += 1 }
            restored.startMonitoringCountdown()
            restored.refreshCountdown()
            expect(restoredCompletions == 0, "relaunch does not replay completion")
            store.restartCountdown()
            expect(store.goal.countdown?.isFinished == false, "restart clears handled flag")
            clock.advance(10)
            store.refreshCountdown()
            expect(completions == 2, "restarted timer delivers a new completion")
            store.startCountdown(seconds: 10)
            store.clearCountdown()
            clock.advance(100)
            store.refreshCountdown()
            expect(completions == 2, "cleared timer cannot sound later")
            store.startCountdown(seconds: 10)
            store.complete()
            clock.advance(100)
            store.refreshCountdown()
            expect(completions == 2 && store.goal == OneGoal(), "completed goal cancels the timer")
            store.save(text: "A new goal")
            store.startCountdown(seconds: 1)
            clock.advance(2)
            store.pauseCountdown()
            expect(completions == 3 && store.goal.countdown?.isFinished == true, "pause at expiry finishes once instead of freezing at zero")
        }
    }

    @MainActor
    private static func completionScheduler() {
        withStore { _, clock, store in
            var completions = 0
            store.onCountdownFinished = { completions += 1 }
            store.startMonitoringCountdown()
            store.save(text: "A goal with a monitored deadline")
            store.startCountdown(seconds: 1)
            clock.advance(2)
            // Pump only this test process's run loop. No app, windows, or input events.
            let timeout = Date().addingTimeInterval(4)
            while completions == 0 && Date() < timeout {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            expect(completions == 1, "real Foundation timer delivers completion without a manual refresh")
            expect(store.goal.countdown?.isFinished == true, "scheduled completion persists finished state")
            store.refreshCountdown()
            expect(completions == 1, "scheduled completion cannot be replayed")
        }
    }

    @MainActor
    private static func legacySnapshots() throws {
        try withStore { defaults, clock, _ in
            let legacy: [String: Any] = ["text": "Legacy goal", "countdown": [
                "duration": 60, "deadline": clock.now.addingTimeInterval(60).timeIntervalSinceReferenceDate
            ]]
            defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: OneGoalStore.storageKey)
            let restored = OneGoalStore(defaults: defaults, clock: { clock.now })
            expect(restored.goal.text == "Legacy goal", "legacy goal decodes")
            expect(restored.goal.countdown?.isPaused == false, "legacy snapshot has no pause")
            expect(restored.goal.countdown?.isFinished == false, "legacy snapshot has no handled flag")
            var completions = 0
            restored.onCountdownFinished = { completions += 1 }
            clock.advance(120)
            restored.startMonitoringCountdown()
            expect(restored.goal.countdown?.isFinished == true, "expired-at-launch timer is marked finished")
            expect(completions == 0, "expired-at-launch timer is silent")
            restored.startMonitoringCountdown()
            restored.refreshCountdown()
            expect(completions == 0, "repeated startup cannot replay an expired sound")
            restored.startCountdown(seconds: 1)
            clock.advance(1)
            restored.refreshCountdown()
            expect(completions == 1, "new timer after stale expiry can still finish")
        }
    }

    @MainActor
    private static func layoutRules() {
        expect(OneGoalLayout.captionHeight(lineHeight: 8.4, padding: 1) == 12, "caption height fits font and padding")
        for lineHeight: CGFloat in [8.4, 14.2, 29.1] {
            for padding: CGFloat in [0, 1, 6, 12] {
                expect(OneGoalLayout.captionHeight(lineHeight: lineHeight, padding: padding) >= lineHeight + 2 * padding,
                       "automatic height cannot clip the requested font/padding")
            }
        }
        let normal = OneGoalLayout(menuBarHeight: 33, captionHeight: 12, hitPadding: 6, verticalOffset: 12)
        expect(normal.extensionHeight(contentHeight: 33, isPreview: false) == 12, "collapsed extension is one caption high")
        expect(normal.captionOrigin(bodyHeight: 45) == 27, "collapsed caption is at bottom")
        expect(normal.extensionHeight(contentHeight: 190, isPreview: false) == 0, "expanded goal does not add height")
        expect(normal.captionOrigin(bodyHeight: 190) == 172, "expanded caption is at bottom, not header")
        expect(normal.extensionHeight(contentHeight: 60, isPreview: true) == 12, "preview reserves a separate footer")
        expect(normal.captionOrigin(bodyHeight: 72) + 6 == 60, "preview footer does not cover preview content")
        let timerWidth = OneGoalLayout.timerWidth(notchWidth: 267, curveInset: 20)
        expect(timerWidth == 227, "timer uses collapsed inner width")
        expect(OneGoalLayout.timerWidth(notchWidth: 20, curveInset: 20) == 0, "timer width cannot be negative")
        for offset: CGFloat in [-24, -10, 0, 12, 64] {
            for height: CGFloat in [8, 12, 20, 48] {
                let layout = OneGoalLayout(menuBarHeight: 33, captionHeight: height, hitPadding: 6, verticalOffset: offset)
                for content: CGFloat in [33, 60, 190] {
                    for preview in [false, true] {
                        let body = content + layout.extensionHeight(contentHeight: content, isPreview: preview)
                        let origin = layout.captionOrigin(bodyHeight: body)
                        expect(origin >= 0 && origin + 6 + height <= body + 0.001, "caption stays inside unified silhouette")
                        if preview {
                            expect(origin + 6 >= content - 0.001, "preview content is never covered")
                        }
                    }
                }
            }
        }
        expect(OneGoalCompletionSound.allCases.count == 5, "four sounds plus Silent")
    }

    @MainActor
    private static func pausedMediaVisibility() {
        let now = Date()
        expect(MediaVisibilityPolicy.hasCurrentTrack(title: "A track", lastUpdated: now), "real track is available")
        expect(!MediaVisibilityPolicy.hasCurrentTrack(title: " \n", lastUpdated: now), "empty metadata cannot pin media")
        expect(!MediaVisibilityPolicy.hasCurrentTrack(title: "Unknown", lastUpdated: now), "fallback title cannot pin media")
        expect(!MediaVisibilityPolicy.hasCurrentTrack(title: "I'm Handsome", lastUpdated: .distantPast), "startup placeholder cannot pin media")
        for keep in [false, true] {
            for hasTrack in [false, true] {
                expect(MediaVisibilityPolicy.shouldShowPlayer(isPlaying: true, isIdle: true, keepWhilePaused: keep, hasTrack: hasTrack), "playing media is visible")
                expect(MediaVisibilityPolicy.shouldShowPlayer(isPlaying: false, isIdle: false, keepWhilePaused: keep, hasTrack: hasTrack), "pause grace period stays visible")
                expect(MediaVisibilityPolicy.shouldShowPlayer(isPlaying: false, isIdle: true, keepWhilePaused: keep, hasTrack: hasTrack) == (keep && hasTrack), "paused media obeys the option and track availability")
            }
        }
    }

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }
}
