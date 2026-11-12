import Foundation

enum ReminderPhase: String { case current, upcoming, tomorrow, finished, free }

struct ReminderState {
    var phase: ReminderPhase
    var course: CourseOccurrence?
    var next: CourseOccurrence?
    var tomorrow: [CourseOccurrence]
    var deadlines: [ScheduleDeadline]
    var upcomingExams: [CourseOccurrence] = []

    var nextToStart: CourseOccurrence? {
        switch phase {
        case .upcoming: return course
        case .current: return next
        case .tomorrow: return tomorrow.first
        case .finished, .free: return nil
        }
    }
}

enum ReminderEngine {
    static func state(snapshot: ScheduleSnapshot, at now: Date, calendar: Calendar = .current) -> ReminderState {
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow)!
        let events = snapshot.schedule.filter { $0.end > $0.start }
        let examLimit = calendar.date(byAdding: .day, value: 7, to: now)!
        let upcomingExams = events.filter { $0.isExam && $0.start > now && $0.start <= examLimit }
        let today = events.filter { $0.start < tomorrow && $0.end > start }
        let tomorrowEvents = events.filter { $0.start >= tomorrow && $0.start < dayAfter }
        let deadlineLimit = now.addingTimeInterval(TimeInterval(snapshot.settings.reminderHours) * 3600)
        let deadlines = snapshot.pendingDeadlines.filter { $0.deadline <= deadlineLimit }
            .sorted { $0.deadline < $1.deadline }
        if let current = today.first(where: { $0.start <= now && now < $0.end }) {
            return .init(phase: .current, course: current,
                next: today.first { $0.start > now && $0.id != current.id },
                tomorrow: [], deadlines: deadlines, upcomingExams: upcomingExams)
        }
        let future = today.filter { $0.start > now }
        if let upcoming = future.first {
            return .init(phase: .upcoming, course: upcoming, next: future.dropFirst().first,
                tomorrow: [], deadlines: deadlines, upcomingExams: upcomingExams)
        }
        return .init(phase: tomorrowEvents.isEmpty ? (today.isEmpty ? .free : .finished) : .tomorrow,
            course: nil, next: nil, tomorrow: tomorrowEvents, deadlines: deadlines, upcomingExams: upcomingExams)
    }

    static func timelineDates(snapshot: ScheduleSnapshot, now: Date, calendar: Calendar = .current) -> [Date] {
        let limit = calendar.date(byAdding: .day, value: 2, to: now)!
        var dates: Set<Date> = [now, limit]
        for event in snapshot.schedule {
            for date in [event.start, event.end] where date > now && date < limit { dates.insert(date) }
            if event.isExam, let threshold = calendar.date(byAdding: .day, value: -7, to: event.start), threshold > now && threshold < limit {
                dates.insert(threshold)
            }
        }
        for task in snapshot.pendingDeadlines {
            let due = task.deadline
                for date in [due, due.addingTimeInterval(-TimeInterval(snapshot.settings.reminderHours) * 3600)]
                    where date > now && date < limit { dates.insert(date) }
        }
        for day in 1...3 {
            let date = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now))!
            if date < limit { dates.insert(date) }
        }
        return dates.sorted()
    }
}
