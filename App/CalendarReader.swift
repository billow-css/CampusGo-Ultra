import Foundation
import EventKit

struct CalendarReadResult {
    let calendars: [CalendarChoice]
    // nil means a selected calendar disappeared; preserve the cached timetable.
    let events: [CourseOccurrence]?
}

/// All EventKit objects stay on this actor, including potentially blocking XPC queries.
actor CalendarReader {
    private var cachedStore: EKEventStore?

    private func store() -> EKEventStore {
        if let cachedStore { return cachedStore }
        let created = EKEventStore()
        cachedStore = created
        return created
    }

    func requestAccess() async throws -> Bool {
        try await store().requestFullAccessToEvents()
    }

    func calendars(reset: Bool = false) -> [CalendarChoice] {
        let eventStore = store()
        if reset { eventStore.reset() }
        return choices(eventStore.calendars(for: .event))
    }

    func read(calendarIDs: [String], interval: DateInterval) -> CalendarReadResult {
        let eventStore = store()
        let available = eventStore.calendars(for: .event)
        let selectedIDs = Set(calendarIDs)
        let chosen = available.filter { selectedIDs.contains($0.calendarIdentifier) }
        guard chosen.count == selectedIDs.count else {
            return .init(calendars: choices(available), events: nil)
        }
        guard !chosen.isEmpty else { return .init(calendars: choices(available), events: []) }
        let predicate = eventStore.predicateForEvents(withStart: interval.start, end: interval.end, calendars: chosen)
        var seen = Set<String>()
        let events = eventStore.events(matching: predicate).compactMap { event -> CourseOccurrence? in
            guard !event.isAllDay, event.endDate > event.startDate else { return nil }
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let id = event.calendar.calendarIdentifier + "::" + (event.eventIdentifier ?? title)
                + "::" + String(event.startDate.timeIntervalSince1970)
            guard seen.insert(id).inserted else { return nil }
            return .init(id: id, calendarID: event.calendar.calendarIdentifier, title: title,
                start: event.startDate, end: event.endDate, location: event.location ?? "", notes: event.notes ?? "")
        }.sorted { $0.start < $1.start }
        return .init(calendars: choices(available), events: events)
    }

    private func choices(_ calendars: [EKCalendar]) -> [CalendarChoice] {
        calendars.map {
            .init(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title, isSubscribed: $0.type == .subscription)
        }.sorted { ($0.isSubscribed ? 0 : 1, $0.title) < ($1.isSubscribed ? 0 : 1, $1.title) }
    }
}
