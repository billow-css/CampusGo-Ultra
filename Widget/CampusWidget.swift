import SwiftUI
import WidgetKit
import os

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduleSnapshot?
    var isPreview = false
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry { preview() }
    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(context.isPreview ? preview() : .init(date: Date(), snapshot: load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let now = Date()
        guard let snapshot = load() else {
            completion(Timeline(entries: [.init(date: now, snapshot: nil)], policy: .after(now.addingTimeInterval(900))))
            return
        }
        let dates = ReminderEngine.timelineDates(snapshot: snapshot, now: now)
        completion(Timeline(entries: dates.map { .init(date: $0, snapshot: snapshot) },
            policy: .after(dates.last!.addingTimeInterval(1))))
    }
    private func load() -> ScheduleSnapshot? {
        let logger = Logger(subsystem: "com.campusschedule.mac.widget", category: "SharedSchedule")
        guard let repository = SharedRepository.widget() else {
            logger.error("Shared timetable container unavailable")
            return nil
        }
        do {
            guard let snapshot = try repository.load() else {
                logger.notice("Shared timetable file not found")
                return nil
            }
            logger.notice("Shared timetable loaded: \(snapshot.occurrences.count, privacy: .public) occurrences, \(snapshot.examRecords.count, privacy: .public) exams")
            return snapshot
        } catch {
            logger.error("Shared timetable read failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
    private func preview() -> ScheduleEntry {
        let now = Date()
        var snapshot = ScheduleSnapshot(now: now)
        let start = now.addingTimeInterval(-1200)
        let event = CourseOccurrence(id: "preview", calendarID: "preview", title: "高等数学",
            start: start, end: now.addingTimeInterval(2400), location: "A302", notes: "")
        snapshot.occurrences = [event]
        snapshot.registerCourses([event])
        snapshot.profiles[0].teacher = "王老师"
        return .init(date: now, snapshot: snapshot, isPreview: true)
    }
}

struct ScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry
    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                VStack(alignment: .leading) {
                    WidgetBoard(snapshot: snapshot, now: entry.date, compact: family == .systemMedium)
                    if family == .systemLarge { Spacer(minLength: 0) }
                    if let syncedAt = snapshot.syncedAt,
                        entry.date.timeIntervalSince(syncedAt) > 86400 {
                        Text("课表同步于 " + syncedAt.formatted(.dateTime.month().day()))
                            .font(.system(size: 10)).foregroundStyle(CampusTheme.boardSecondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "calendar").font(.title2)
                    Text("CampusGo Ultra").font(.headline)
                    Text("打开应用，选择课表日历并完成一次同步。").font(.caption)
                }.foregroundStyle(CampusTheme.boardText)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(CampusTheme.reminderSurface(entry.snapshot, at: entry.date), for: .widget)
            .widgetURL(URL(string: "campusschedule://today"))
    }
}

@main
struct CampusScheduleWidget: Widget {
    let kind = "CampusScheduleWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in ScheduleWidgetView(entry: entry) }
            .configurationDisplayName("CampusGo Ultra · 课程登机牌")
            .description("新版登机牌：课程、考试、倒计时与作业截止提醒。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
