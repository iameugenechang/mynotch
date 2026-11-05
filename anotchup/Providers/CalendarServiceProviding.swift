//
//  CalendarServiceProvider.swift
//  Calendr
//
//  Created by Paker on 31/12/20.
//  Original source: Original source: https://github.com/pakerwreah/Calendr
//  Modified by Alexander on 08/06/25
//

import Foundation
import CalendarFeature
@preconcurrency import EventKit

@MainActor
protocol CalendarServiceProviding {
    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus
    func setReminderCompleted(reminderID: String, completed: Bool) async throws
    func requestAccess(to type: EKEntityType) async throws -> Bool
    func calendars() async -> [CalendarModel]
    func events(from start: Date, to end: Date, calendars: [String]) async throws -> [EventModel]
}

@MainActor
protocol CalendarBackend {
    func status(for type: EKEntityType) -> EKAuthorizationStatus
    func request(_ type: EKEntityType) async throws -> Bool
    func calendars(for type: EKEntityType) -> [CalendarModel]
    func events(from start: Date, to end: Date, ids: [String], type: EKEntityType) async throws -> [EventModel]
    func complete(_ id: String, completed: Bool) throws
}

class CalendarService: CalendarServiceProviding {
    private let backend: any CalendarBackend

    init(backend: any CalendarBackend) { self.backend = backend }
    convenience init(store: EKEventStore = EKEventStore()) {
        self.init(backend: EventKitCalendarBackend(store: store))
    }

    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus { backend.status(for: type) }
    func requestAccess(to type: EKEntityType) async throws -> Bool { try await backend.request(type) }
    private func hasAccess(to type: EKEntityType) -> Bool { authorizationStatus(for: type) == .fullAccess }

    func calendars() async -> [CalendarModel] {
        [EKEntityType.event, .reminder].filter { hasAccess(to: $0) }.flatMap { backend.calendars(for: $0) }
    }
    func events(from start: Date, to end: Date, calendars ids: [String]) async throws -> [EventModel] {
        guard !ids.isEmpty else { return [] }
        guard hasAccess(to: .event) || hasAccess(to: .reminder) else { throw CalendarQueryError.accessDenied }
        var result: [EventModel] = []
        for type in [EKEntityType.event, .reminder] where hasAccess(to: type) {
            let selected = backend.calendars(for: type).filter { ids.contains($0.id) }.map(\.id)
            guard !selected.isEmpty else { continue }
            let values = try await backend.events(from: start, to: end, ids: selected, type: type)
            result += values.filter {
                selected.contains($0.calendar.id) && ($0.calendar.isReminder || $0.end <= $0.start
                    ? $0.start >= start && $0.start < end : $0.start < end && $0.end > start)
            }
        }
        return result.sorted { $0.start < $1.start }
    }
    func setReminderCompleted(reminderID: String, completed: Bool) async throws {
        guard hasAccess(to: .reminder) else { throw CalendarQueryError.accessDenied }
        try backend.complete(reminderID, completed: completed)
    }
}

private class EventKitCalendarBackend: CalendarBackend {
    private let store: EKEventStore
    init(store: EKEventStore) { self.store = store }
    func status(for type: EKEntityType) -> EKAuthorizationStatus { EKEventStore.authorizationStatus(for: type) }
    
    @MainActor
    func request(_ type: EKEntityType) async throws -> Bool {
        if #available(macOS 14.0, *) {
            switch type {
            case .event:
                return try await store.requestFullAccessToEvents()
            case .reminder:
                return try await store.requestFullAccessToReminders()
            @unknown default:
                return false
            }
        } else {
            return try await store.requestAccess(to: type)
        }
    }
    
    func calendars(for type: EKEntityType) -> [CalendarModel] {
        store.calendars(for: type).map { CalendarModel(from: $0) }
    }

    func events(from start: Date, to end: Date, ids: [String], type: EKEntityType) async throws -> [EventModel] {
        let calendars = store.calendars(for: type).filter { ids.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }
        if type == .event {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            return store.events(matching: predicate).compactMap { EventModel(from: $0) }
        }
        return try await fetchReminders(from: start, to: end, calendars: calendars)
    }
    
    private func fetchReminders(from start: Date, to end: Date, calendars: [EKCalendar]) async throws -> [EventModel] {
        return try await withCheckedThrowingContinuation { continuation in
            // Create predicate for reminders with due dates in the specified range
            let predicate = store.predicateForReminders(in: calendars)
            
            store.fetchReminders(matching: predicate) { reminders in
                
                guard let reminders else {
                    continuation.resume(throwing: CalendarQueryError.unavailable)
                    return
                }
                let filteredReminders = reminders.filter { reminder in
                    // Check if reminder has a due date within our range
                    guard let dueDate = reminder.dueDateComponents?.date else {
                        return false
                    }
                    
                    return dueDate >= start && dueDate < end
                }
                
                // Convert to EventModel
                let eventModels = filteredReminders.compactMap { reminder in
                    EventModel(from: reminder)
                }
                
                continuation.resume(returning: eventModels)
            }
        }
    }
    
    func complete(_ id: String, completed: Bool) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw CalendarQueryError.unavailable
        }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }
}

// MARK: - Model Extensions

extension CalendarModel {
    init(from calendar: EKCalendar) {
        self.init(
            id: calendar.calendarIdentifier,
            account: calendar.accountTitle,
            title: calendar.title,
            color: calendar.color,
            isSubscribed: calendar.isSubscribed || calendar.isDelegate,
            isReminder: calendar.allowedEntityTypes.contains(.reminder)
        )
    }
}

extension EventModel {
    init?(from event: EKEvent) {
        guard let calendar = event.calendar else { return nil }
        
        self.init(
            id: event.calendarItemIdentifier,
            start: event.startDate,
            end: event.endDate,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url,
            isAllDay: event.shouldBeAllDay,
            type: .init(from: event),
            calendar: .init(from: calendar),
            participants: .init(from: event),
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : event.timeZone,
            hasRecurrenceRules: event.hasRecurrenceRules || event.isDetached,
            priority: nil
        )
    }
    
    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar,
              let dueDateComponents = reminder.dueDateComponents,
              let date = Calendar.current.date(from: dueDateComponents)
        else { return nil }
        
        self.init(
            id: reminder.calendarItemIdentifier,
            start: date,
            end: Calendar.current.endOfDay(for: date),
            title: reminder.title ?? "",
            location: reminder.location,
            notes: reminder.notes,
            url: reminder.url,
            isAllDay: dueDateComponents.hour == nil,
            type: .reminder(completed: reminder.isCompleted),
            calendar: .init(from: calendar),
            participants: [],
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : reminder.timeZone,
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            priority: .init(from: reminder.priority)
        )
    }
}

extension EventType {
    init(from event: EKEvent) {
        self = event.birthdayContactIdentifier != nil ? .birthday : .event(.init(from: event.currentUser?.participantStatus))
    }
}

extension AttendanceStatus {
    init(from status: EKParticipantStatus?) {
        switch status {
        case .accepted:
            self = .accepted
        case .tentative:
            self = .maybe
        case .declined:
            self = .declined
        case .pending:
            self = .pending
        default:
            self = .unknown
        }
    }
}

extension Array where Element == Participant {
    init(from event: EKEvent) {
        var participants = event.attendees ?? []
        if let organizer = event.organizer, !participants.contains(where: { $0.url == organizer.url }) {
            participants.append(organizer)
        }
        self.init(
            participants.map { .init(from: $0, isOrganizer: $0.url == event.organizer?.url) }
        )
    }
}

extension Participant {
    init(from participant: EKParticipant, isOrganizer: Bool) {
        self.init(
            name: participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            status: .init(from: participant.participantStatus),
            isOrganizer: isOrganizer,
            isCurrentUser: participant.isCurrentUser
        )
    }
}

extension Priority {
    init?(from p: Int) {
        switch p {
        case 1...4:
            self = .high
        case 5:
            self = .medium
        case 6...9:
            self = .low
        default:
            return nil
        }
    }
}

// MARK: - Helper Extensions

private extension EKCalendar {
    var accountTitle: String {
        switch source.sourceType {
        case .local, .subscribed, .birthdays:
            return "Other"
        default:
            return source.title
        }
    }
    
    var isDelegate: Bool {
        if #available(macOS 13.0, *) {
            return source.isDelegate
        } else {
            return false
        }
    }
}

private extension EKEvent {
    var currentUser: EKParticipant? {
        attendees?.first(where: \.isCurrentUser)
    }
    
    var shouldBeAllDay: Bool {
        guard !isAllDay else { return true }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.dateInterval(of: .day, for: endDate)?.end
        return startDate == startOfDay && endDate == endOfDay
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        dateInterval(of: .day, for: date)?.end ?? date
    }
}
