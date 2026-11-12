import SwiftUI
import Combine

struct HomeView: View {
    @Environment(\.nuistAccent) private var themeAccent
    @EnvironmentObject private var store: AppStore
    let onOpenSchedule: () -> Void
    let onOpenModule: (String, Bool) -> Void
    let onDiscover: () -> Void
    @State private var now = Date()

    var body: some View {
        let dayStart = Calendar.current.startOfDay(for: now)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let today = store.snapshot.schedule.filter { $0.start < dayEnd && $0.end > dayStart }
        let state = ReminderEngine.state(snapshot: store.snapshot, at: now)
        let featured = state.course ?? state.tomorrow.first
        let upcoming = state.phase == .tomorrow ? state.tomorrow : today.filter { $0.end > now }
        let following = upcoming.filter { $0.id != featured?.id }
        let otherExams = state.upcomingExams.filter { $0.id != featured?.id }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(now.formatted(.dateTime.month().day().weekday(.wide)))
                            .font(.system(size: 19, weight: .semibold))
                        Text("今日 \(today.count) 节课  ·  \(store.snapshot.homeworkRecords.filter { !$0.isCompleted }.count) 份作业待完成  ·  \(store.snapshot.todos.filter { !$0.isCompleted }.count) 项待办")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onOpenSchedule) { Label("本周课表", systemImage: "arrow.up.right") }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    HomeHeroCard(snapshot: store.snapshot, now: tick.date)
                }
                if !otherExams.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("接下来的考试").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        ExamNotice(exams: otherExams)
                    }
                }
                if !state.deadlines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("即将截止").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(Array(state.deadlines.prefix(3))) { item in
                            HStack {
                                Image(systemName: item.icon).foregroundStyle(themeAccent)
                                Text(item.displayTitle).font(.system(size: 13)).lineLimit(1)
                                Spacer()
                                Text(item.deadline, format: .dateTime.month().day().hour().minute())
                                    .font(.system(size: 11)).foregroundStyle(item.deadline < now ? Color.orange : Color.secondary)
                            }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                if !following.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(state.phase == .tomorrow ? "明天的后续行程" : "之后的行程")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        LazyVStack(spacing: 8) { ForEach(following) { event in courseRow(event) } }
                    }
                }
                let ended = today.filter { $0.end <= now }
                if !ended.isEmpty {
                    DisclosureGroup("今日已结束 · \(ended.count) 项") {
                        LazyVStack(spacing: 8) { ForEach(ended) { event in courseRow(event) } }.padding(.top, 10)
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                }
                SummaryModulesView(onOpen: onOpenModule, onDiscover: onDiscover)
            }.padding(26)
        }.onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func courseRow(_ event: CourseOccurrence) -> some View {
        let ink = event.isExam ? CampusTheme.examAccent : CampusTheme.courseAccent(for: event, in: store.snapshot)
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2).fill(ink).frame(width: 3)
            Text(ScheduleFormat.timeRange(event)).font(.system(size: 12, design: .monospaced)).frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text((event.isExam ? "考试 · " : "") + event.title).font(.system(size: 14, weight: .medium))
                Text([event.location, store.snapshot.profile(for: event)?.teacher ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if event.end <= now {
                Text("已结束").font(.caption).foregroundStyle(.secondary)
            } else if event.start <= now {
                Text(event.isExam ? "正在考试" : "正在上课").font(.caption).foregroundStyle(ink)
            }
            if let profile = store.snapshot.profile(for: event) { CourseIDBadge(text: profile.shortID, small: true, ink: ink) }
        }.padding(12).fixedSize(horizontal: false, vertical: true)
            .background(ink.opacity(event.start <= now && now < event.end ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 9))
    }
}
