import Combine
import Foundation

public enum CalendarQueryError: Error, Equatable {
    case accessDenied
    case unavailable
}

/// Half-open local-day range. An empty selection means no calendars, not all.
public struct CalendarQuery: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let calendarIDs: Set<String>

    public init(date: Date, calendarIDs: Set<String>, calendar: Calendar) {
        let day = calendar.dateInterval(of: .day, for: date)!
        start = day.start
        end = day.end
        self.calendarIDs = calendarIDs
    }

    public func includes(start: Date, end: Date, isReminder: Bool) -> Bool {
        if isReminder || start == end { return start >= self.start && start < self.end }
        return start < self.end && end > self.start
    }
}

public enum CalendarLoadStatus: Equatable {
    case idle, loading, loaded, denied, stopped
    case failed(String)
}

/// The adapter owns EventKit and authorization prompts. Loading never prompts.
/// Adapter failures must throw; an empty successful result is not a failure.
@MainActor
public final class CalendarQuerySession<Event>: ObservableObject {
    @Published public private(set) var events: [Event] = []
    @Published public private(set) var status: CalendarLoadStatus = .idle
    private let fetch: @MainActor (CalendarQuery) async throws -> [Event]
    private var revision = UUID()
    private var stopped = false

    public init(fetch: @escaping @MainActor (CalendarQuery) async throws -> [Event]) {
        self.fetch = fetch
    }

    public func load(_ query: CalendarQuery) async {
        guard !stopped else { return }
        let request = UUID()
        revision = request
        status = .loading
        do {
            let result = query.calendarIDs.isEmpty ? [] : try await fetch(query)
            guard !stopped, revision == request, !Task.isCancelled else { return }
            events = result
            status = .loaded
        } catch {
            guard !stopped, revision == request, !Task.isCancelled else { return }
            events = []
            status = (error as? CalendarQueryError) == .accessDenied
                ? .denied : .failed(String(describing: error))
        }
    }

    public func cancel() {
        guard !stopped else { return }
        revision = UUID()
        status = .idle
    }

    public func stop() {
        stopped = true
        revision = UUID()
        events = []
        status = .stopped
    }
}
