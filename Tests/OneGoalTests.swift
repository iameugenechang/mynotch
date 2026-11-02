import Foundation

// Run with scripts/test-one-goal.sh. Uses an isolated preferences suite.
@main
struct OneGoalTests {
    @MainActor
    static func main() throws {
        let suite = "mynotch.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let store = OneGoalStore(defaults: defaults)

        expect(store.goal == OneGoal(), "starts empty")
        store.startCountdown(minutes: 25, now: start)
        expect(store.goal.countdown == nil, "cannot time an empty goal")
        store.save(text: " \nSend  the\tproposal to Maya \n")
        expect(store.goal.text == "Send the proposal to Maya", "normalizes whitespace")
        expect(OneGoalStore(defaults: defaults).goal == store.goal, "persists across store recreation")
        store.startCountdown(minutes: 25, now: start)
        let countdown = store.goal.countdown!
        expect(countdown.duration == 1500, "stores original duration")
        expect(countdown.fractionRemaining(at: start) == 1, "starts full")
        expect(countdown.fractionRemaining(at: start.addingTimeInterval(750)) == 0.5, "ring shows remaining fraction")
        expect(countdown.remainingText(at: start.addingTimeInterval(1)) == "24:59", "formats countdown")
        expect(countdown.remainingText(at: start.addingTimeInterval(1499.5)) == "0:01", "rounds remaining partial seconds up")
        expect(countdown.remainingText(at: start.addingTimeInterval(3000)) == "0:00", "stops at zero")
        expect(countdown.fractionRemaining(at: start.addingTimeInterval(-100)) == 1, "clock rollback cannot overflow ring")
        expect(OneGoalStore(defaults: defaults).goal.countdown == countdown, "deadline survives restart")
        expect(countdown.remainingText(at: start.addingTimeInterval(1200)) == "5:00", "sleep does not pause countdown")
        expect(store.goal.text == "Send the proposal to Maya", "expiry does not complete goal")

        store.save(text: "Send the revised proposal")
        expect(store.goal.countdown == countdown, "editing preserves countdown")
        for invalid in [-1, 0, 1441, Int.max] {
            store.startCountdown(minutes: invalid, now: start)
            expect(store.goal.countdown == countdown, "rejects invalid duration \(invalid)")
        }
        store.clearCountdown()
        expect(store.goal.countdown == nil && !store.goal.text.isEmpty, "clearing countdown keeps goal")
        store.startCountdown(minutes: 1, now: start)
        store.complete()
        expect(store.goal == OneGoal(), "completion clears everything")
        expect(defaults.object(forKey: OneGoalStore.storageKey) == nil, "completion deletes persisted state")
        expect(OneGoalStore(defaults: defaults).goal == OneGoal(), "completed goal cannot reappear on restart")
        store.save(text: "Another goal")
        store.startCountdown(minutes: 1, now: start)
        store.save(text: " \n\t ")
        expect(store.goal == OneGoal(), "empty save clears text and countdown")
        expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("oneGoal.") }.isEmpty, "no history keys")

        defaults.set(Data("not json".utf8), forKey: OneGoalStore.storageKey)
        expect(OneGoalStore(defaults: defaults).goal == OneGoal(), "invalid saved data is safe")
        let invalid = OneGoal(text: "Keep this goal", countdown: .init(duration: -1, deadline: start))
        defaults.set(try JSONEncoder().encode(invalid), forKey: OneGoalStore.storageKey)
        let repaired = OneGoalStore(defaults: defaults)
        expect(repaired.goal.text == "Keep this goal" && repaired.goal.countdown == nil, "invalid countdown keeps text")
        let empty = OneGoal(text: "  ", countdown: .init(duration: 60, deadline: start))
        defaults.set(try JSONEncoder().encode(empty), forKey: OneGoalStore.storageKey)
        expect(OneGoalStore(defaults: defaults).goal == OneGoal(), "orphan countdown is discarded")
        print("One Goal: \(checks) checks passed")
    }

    @MainActor private static var checks = 0

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }
}
