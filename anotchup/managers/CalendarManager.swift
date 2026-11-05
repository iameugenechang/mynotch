//
//  CalendarManager.swift
//  anotchup
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import CalendarFeature
import Combine
import Defaults
import EventKit
import SwiftUI

/// Native presentation/preferences facade. Query ownership lives in CalendarFeature.
@MainActor
class CalendarManager: ObservableObject {
    static let shared = makeAppCalendarManager()

    @Published var currentWeekStartDate: Date
    @Published private(set) var events: [EventModel] = []
    @Published private(set) var loadStatus: CalendarLoadStatus = .idle
    @Published private(set) var mutationError: String?
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var reminderLists: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    private let calendarService: any CalendarServiceProviding
    private let querySession: CalendarQuerySession<EventModel>
    private let notificationCenter: NotificationCenter
    private var subscriptions = Set<AnyCancellable>()
    private var listRevision = UUID()
    private var stopped = false

    init(service: any CalendarServiceProviding, notificationCenter: NotificationCenter = .default,
         date: Date = Date()) {
        calendarService = service
        self.notificationCenter = notificationCenter
        currentWeekStartDate = CalendarManager.startOfDay(date)
        querySession = CalendarQuerySession { query in
            try await service.events(from: query.start, to: query.end, calendars: Array(query.calendarIDs))
                .filter { query.calendarIDs.contains($0.calendar.id) &&
                    query.includes(start: $0.start, end: $0.end, isReminder: $0.calendar.isReminder) }
        }
        querySession.$events.sink { [weak self] in self?.events = $0 }.store(in: &subscriptions)
        querySession.$status.sink { [weak self] in self?.loadStatus = $0 }.store(in: &subscriptions)
        notificationCenter.publisher(for: .EKEventStoreChanged).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reloadCalendarAndReminderLists()
                await self?.updateEvents()
            }
        }.store(in: &subscriptions)
        Task { [weak self] in await self?.reloadCalendarAndReminderLists() }
    }

    func stop() {
        stopped = true
        listRevision = UUID()
        subscriptions.removeAll()
        querySession.stop()
        events = []
        loadStatus = .stopped
    }

    func reloadCalendarAndReminderLists() async {
        guard !stopped else { return }
        let revision = UUID()
        listRevision = revision
        let all = await calendarService.calendars()
        guard !stopped, revision == listRevision, !Task.isCancelled else { return }
        eventCalendars = all.filter { !$0.isReminder }
        reminderLists = all.filter { $0.isReminder }
        allCalendars = all
        updateSelectedCalendars()
    }

    func checkCalendarAuthorization() async { await checkAuthorization(for: .event) }
    func checkReminderAuthorization() async { await checkAuthorization(for: .reminder) }

    private func checkAuthorization(for type: EKEntityType) async {
        guard !stopped else { return }
        var status = calendarService.authorizationStatus(for: type)
        if status == .notDetermined {
            do {
                status = try await calendarService.requestAccess(to: type) ? .fullAccess : .denied
            } catch {
                guard !stopped else { return }
                mutationError = String(describing: error)
            }
        }
        guard !stopped, !Task.isCancelled else { return }
        if type == .event { calendarAuthorizationStatus = status }
        else { reminderAuthorizationStatus = status }
        await reloadCalendarAndReminderLists()
        await updateEvents()
    }

    func updateSelectedCalendars() {
        querySession.cancel()
        switch Defaults[.calendarSelectionState] {
        case .all: selectedCalendarIDs = Set(allCalendars.map { $0.id })
        case .selected(let identifiers): selectedCalendarIDs = identifiers
        }
    }

    func getCalendarSelected(_ calendar: CalendarModel) -> Bool { selectedCalendarIDs.contains(calendar.id) }

    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]
        switch selectionState {
        case .all:
            if !isSelected {
                selectionState = .selected(Set(allCalendars.map { $0.id }).subtracting([calendar.id]))
            }
        case .selected(var identifiers):
            if isSelected { identifiers.insert(calendar.id) }
            else { identifiers.remove(calendar.id) }
            selectionState = identifiers.isEmpty || identifiers.count == allCalendars.count
                ? .all : .selected(identifiers)
        }
        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents()
    }

    static func startOfDay(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = CalendarManager.startOfDay(date)
        await updateEvents()
    }

    private func updateEvents() async {
        guard !stopped else { return }
        await querySession.load(CalendarQuery(date: currentWeekStartDate,
            calendarIDs: selectedCalendarIDs, calendar: .current))
    }

    func setReminderCompleted(reminderID: String, completed: Bool) async {
        guard !stopped else { return }
        do {
            try await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
            guard !stopped, !Task.isCancelled else { return }
            mutationError = nil
            await updateEvents()
        } catch {
            guard !stopped, !Task.isCancelled else { return }
            mutationError = String(describing: error)
        }
    }
}
