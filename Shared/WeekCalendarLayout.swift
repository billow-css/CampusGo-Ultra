import Foundation

/// Build the week's geometry once; drawing a time label must not rebuild the timetable.
struct WeekCalendarLayout {
    let days: [Date]
    let events: [CourseOccurrence]
    let deadlines: [ScheduleDeadline]
    let startMinute: Int
    let endMinute: Int
    let scale: CalendarTimeScale
    let placements: [Date: [PlacedCourse]]

    init(snapshot: ScheduleSnapshot, monday: Date, calendar: Calendar = .current) {
        let dates = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: monday)!
        let events = snapshot.schedule.filter { $0.start < weekEnd && $0.end > monday }
        let start = min(480, events.map { ScheduleFormat.minuteOfDay($0.start, calendar: calendar) }.min() ?? 480) / 60 * 60
        let end = min(1440, max(1260, events.map { ScheduleFormat.minuteOfDay($0.end, calendar: calendar) + 30 }.max() ?? 1260))
        var occupied: [(Int, Int)] = []
        var placements: [Date: [PlacedCourse]] = [:]
        for day in dates {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            let items = events.filter { $0.start < dayEnd && $0.end > day }
            placements[day] = CalendarPlacement.layout(items)
            occupied.append(contentsOf: items.map {
                ($0.start < day ? 0 : ScheduleFormat.minuteOfDay($0.start, calendar: calendar),
                 $0.end >= dayEnd ? 1440 : ScheduleFormat.minuteOfDay($0.end, calendar: calendar))
            })
        }
        self.days = dates
        self.events = events
        self.startMinute = start
        self.endMinute = end
        self.placements = placements
        self.scale = CalendarTimeScale(start: start, end: end, periods: snapshot.settings.periods, occupied: occupied)
        self.deadlines = snapshot.pendingDeadlines.filter { $0.deadline >= monday && $0.deadline < weekEnd }
            .sorted { $0.deadline < $1.deadline }
    }
}
