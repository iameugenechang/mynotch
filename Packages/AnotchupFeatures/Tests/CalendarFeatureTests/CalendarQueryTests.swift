import CalendarFeature
import XCTest

final class CalendarQueryTests: XCTestCase {
    private func query(ids: Set<String> = ["work"]) -> CalendarQuery {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        return CalendarQuery(date: date, calendarIDs: ids, calendar: calendar)
    }

    func testHalfOpenDayAndDST() {
        let q = query()
        XCTAssertEqual(q.end.timeIntervalSince(q.start), 23 * 3600)
        XCTAssertTrue(q.includes(start: q.start, end: q.start, isReminder: true))
        XCTAssertFalse(q.includes(start: q.end, end: q.end, isReminder: true))
        XCTAssertTrue(q.includes(start: q.start.addingTimeInterval(-60), end: q.end, isReminder: false))
        XCTAssertFalse(q.includes(start: q.start.addingTimeInterval(-60), end: q.start, isReminder: false))
    }

    @MainActor
    func testEmptySelectionNeverFetchesAndFailureIsNotEmptySuccess() async {
        var calls = 0
        let session = CalendarQuerySession<String> { _ in
            calls += 1
            throw CalendarQueryError.accessDenied
        }
        await session.load(query(ids: []))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(session.status, .loaded)
        XCTAssertTrue(session.events.isEmpty)
        await session.load(query())
        XCTAssertEqual(session.status, .denied)
        XCTAssertEqual(calls, 1)
        let failure = CalendarQuerySession<String> { _ in throw CalendarQueryError.unavailable }
        await failure.load(query())
        guard case .failed = failure.status else { return XCTFail("failure must not look like an empty success") }
    }

    @MainActor
    func testReplacementAndTerminalStopRejectSuspendedQueries() async {
        var completions: [CheckedContinuation<[String], Error>] = []
        let started = expectation(description: "two queries started")
        started.expectedFulfillmentCount = 2
        let session = CalendarQuerySession<String> { _ in
            try await withCheckedThrowingContinuation {
                completions.append($0)
                started.fulfill()
            }
        }
        let a = Task { await session.load(query()) }
        for _ in 0..<1_000 where completions.isEmpty { try? await Task.sleep(for: .milliseconds(1)) }
        guard !completions.isEmpty else { a.cancel(); return XCTFail("First query did not start") }
        let b = Task { await session.load(query(ids: ["home"])) }
        await fulfillment(of: [started], timeout: 1)
        guard completions.count == 2 else { a.cancel(); b.cancel(); return }
        completions[1].resume(returning: ["new"])
        await b.value
        completions[0].resume(returning: ["old"])
        await a.value
        XCTAssertEqual(session.events, ["new"])
        session.stop()
        await session.load(query())
        XCTAssertEqual(session.status, .stopped)
        XCTAssertTrue(session.events.isEmpty)
        XCTAssertEqual(completions.count, 2)
    }

    @MainActor
    func testCancelRejectsLateFailureAndAllowsReload() async {
        var calls = 0
        var completion: CheckedContinuation<[String], Error>?
        let session = CalendarQuerySession<String> { _ in
            calls += 1
            if calls > 1 { return ["reloaded"] }
            return try await withCheckedThrowingContinuation { completion = $0 }
        }
        let first = Task { await session.load(query()) }
        for _ in 0..<1_000 where completion == nil { try? await Task.sleep(for: .milliseconds(1)) }
        guard completion != nil else { first.cancel(); return XCTFail("Query did not start") }
        session.cancel()
        completion?.resume(throwing: CalendarQueryError.accessDenied)
        await first.value
        XCTAssertEqual(session.status, .idle)
        await session.load(query())
        XCTAssertEqual(session.events, ["reloaded"])
    }
}
