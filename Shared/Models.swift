import Foundation

struct CourseProfile: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var shortID: String
    var teacher = ""

    static func key(calendarID: String, title: String) -> String {
        let normalized = title.precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return calendarID + "::" + normalized
    }

    static func newID(excluding used: Set<String>) -> String {
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        var candidate: String
        repeat { candidate = String((0..<5).map { _ in alphabet.randomElement()! }) }
        while used.contains(candidate)
        return candidate
    }
}

struct CourseOccurrence: Codable, Identifiable, Equatable {
    var id: String
    var calendarID: String
    var title: String
    var start: Date
    var end: Date
    var location: String
    var notes: String
    var examID: UUID?
    var associatedCourseKey: String?
    var isExam: Bool { examID != nil }
    var courseKey: String { associatedCourseKey ?? CourseProfile.key(calendarID: calendarID, title: title) }
}

struct ExamRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var location = ""
    var notes = ""
    var linkedCourseKey: String?
    var sourceOccurrenceID: String?
    var sourceCourseKey: String?
    var sourceStart: Date?

    var occurrence: CourseOccurrence {
        .init(id: "exam:" + id.uuidString, calendarID: "manual-exams", title: title,
            start: start, end: end, location: location, notes: notes,
            examID: id, associatedCourseKey: linkedCourseKey)
    }

    func replaces(_ event: CourseOccurrence) -> Bool {
        guard sourceOccurrenceID != nil else { return false }
        return event.id == sourceOccurrenceID || (event.courseKey == sourceCourseKey && event.start == sourceStart)
    }

    static func marking(_ event: CourseOccurrence) -> ExamRecord {
        .init(title: event.title, start: event.start, end: event.end, location: event.location, notes: event.notes,
            linkedCourseKey: event.courseKey, sourceOccurrenceID: event.id,
            sourceCourseKey: event.courseKey, sourceStart: event.start)
    }
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var icon = "checklist"
    var scheduledAt: Date?
    var deadline: Date?
    var isPinned = false
    var isCompleted = false
    var createdAt = Date()
}

struct LessonPeriod: Codable, Identifiable, Equatable {
    var number: Int
    var startMinute: Int
    var endMinute: Int
    var id: Int { number }

    static let defaults: [LessonPeriod] = [
        .init(number: 1, startMinute: 480, endMinute: 525),
        .init(number: 2, startMinute: 535, endMinute: 580),
        .init(number: 3, startMinute: 610, endMinute: 655),
        .init(number: 4, startMinute: 665, endMinute: 710),
        .init(number: 5, startMinute: 825, endMinute: 870),
        .init(number: 6, startMinute: 880, endMinute: 925),
        .init(number: 7, startMinute: 955, endMinute: 1000),
        .init(number: 8, startMinute: 1010, endMinute: 1055),
        .init(number: 9, startMinute: 1125, endMinute: 1170),
        .init(number: 10, startMinute: 1180, endMinute: 1225)
    ]
}

struct ScheduleSettings: Codable, Equatable {
    var calendarIDs: [String] = []
    var semesterStart: Date
    var semesterEnd: Date
    var reminderHours = 24
    var periods = LessonPeriod.defaults

    init(now: Date = Date(), calendar: Calendar = .current) {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let autumn = month >= 8 || month == 1
        let startYear = month == 1 ? year - 1 : year
        semesterStart = calendar.date(from: DateComponents(year: autumn ? startYear : year,
            month: autumn ? 8 : 2, day: 1))!
        semesterEnd = calendar.date(from: DateComponents(year: autumn ? startYear + 1 : year,
            month: autumn ? 1 : 7, day: 31))!
    }

    func interval(calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: semesterStart)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: semesterEnd))!
        return DateInterval(start: start, end: max(start.addingTimeInterval(86400), end))
    }
}

struct ScheduleSnapshot: Codable, Equatable {
    var schemaVersion = 1
    var settings: ScheduleSettings
    var profiles: [CourseProfile] = []
    var occurrences: [CourseOccurrence] = []
    var todos: [TodoItem] = []
    var syncedAt: Date?
    var importedCalendar: ImportedCalendar?
    // Optional for compatibility with snapshots saved before exam support.
    var exams: [ExamRecord]?
    var homework: [HomeworkAssignment]?
    var usedHomeworkNumbers: [String]?
    var reviews: [LegacyReviewRecord]?

    init(now: Date = Date()) { settings = ScheduleSettings(now: now) }

    func profile(for occurrence: CourseOccurrence) -> CourseProfile? {
        profiles.first { $0.id == occurrence.courseKey }
    }

    var examRecords: [ExamRecord] { exams ?? [] }
    var hasUserData: Bool {
        !profiles.isEmpty || !occurrences.isEmpty || !todos.isEmpty || !examRecords.isEmpty || !homeworkRecords.isEmpty ||
            !(usedHomeworkNumbers ?? []).isEmpty || !(reviews ?? []).isEmpty ||
            !settings.calendarIDs.isEmpty || importedCalendar != nil
    }

    var schedule: [CourseOccurrence] {
        let records = examRecords.filter { $0.end > $0.start && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let courses = occurrences.filter { event in !records.contains { $0.replaces(event) } }
        return (courses + records.map(\.occurrence)).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.isExam != $1.isExam { return $0.isExam }
            return $0.id < $1.id
        }
    }

    @discardableResult
    mutating func upsertExam(_ exam: ExamRecord) -> Bool {
        var clean = exam
        clean.title = exam.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.title.isEmpty, clean.end > clean.start else { return false }
        registerCourses([clean.occurrence])
        var records = examRecords
        if let index = records.firstIndex(where: { $0.id == clean.id ||
            (clean.sourceOccurrenceID != nil && $0.sourceOccurrenceID == clean.sourceOccurrenceID) }) {
            clean.id = records[index].id
            records[index] = clean
        } else { records.append(clean) }
        exams = records
        return true
    }

    mutating func removeExam(_ id: UUID) { exams = examRecords.filter { $0.id != id } }

    mutating func registerCourses(_ events: [CourseOccurrence]) {
        var keys = Set(profiles.map(\.id))
        var used = Set(profiles.map(\.shortID))
        used.formUnion(usedHomeworkNumbers ?? [])
        used.formUnion(homeworkRecords.map(\.number))
        for event in events where !keys.contains(event.courseKey) {
            let id = CourseProfile.newID(excluding: used)
            profiles.append(.init(id: event.courseKey, title: event.title, shortID: id))
            keys.insert(event.courseKey)
            used.insert(id)
        }
    }
}

struct ImportedCalendar: Codable, Equatable {
    var name: String
    var sourceID: String
    var subscriptionURL: String?
    var events: [CourseOccurrence]
}

enum ScheduleFormat {
    static func time(_ date: Date) -> String { minute(minuteOfDay(date)) }
    static func timeRange(_ event: CourseOccurrence) -> String { "\(time(event.start))–\(time(event.end))" }
    static func minute(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
    static func periodLabel(_ event: CourseOccurrence, periods: [LessonPeriod], calendar: Calendar = .current) -> String {
        let start = minuteOfDay(event.start, calendar: calendar)
        let end = calendar.isDate(event.start, inSameDayAs: event.end) ? minuteOfDay(event.end, calendar: calendar) : 1440
        let matching = periods.filter { $0.startMinute < end && $0.endMinute > start }
        guard let first = matching.first, let last = matching.last else { return "" }
        return first.number == last.number ? "第 \(first.number) 节" : "第 \(first.number)–\(last.number) 节"
    }
    static func monday(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }
}
