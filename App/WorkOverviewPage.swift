import SwiftUI
import Combine

struct WorkOverviewPage: View {
    @EnvironmentObject private var store: AppStore
    @State private var now = Date()
    var body: some View {
        let summary = WorkSummary(snapshot: store.snapshot, now: now)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("作业与日程").font(.system(size: 23, weight: .semibold))
                Spacer()
                Text(now.formatted(.dateTime.month().day().weekday(.wide)))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 20)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    WorkStatusBoard(kind: .todos, summary: summary, snapshot: store.snapshot, now: now)
                        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 10)
                    TodoListView().frame(maxHeight: .infinity)
                }.frame(minWidth: 300, idealWidth: 350, maxWidth: 400, maxHeight: .infinity)
                VStack(spacing: 0) {
                    WorkStatusBoard(kind: .homework, summary: summary, snapshot: store.snapshot, now: now)
                        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 10)
                    HomeworkListView(spacious: true).frame(maxHeight: .infinity)
                }.frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }
        }.onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

struct WorkStatusBoard: View {
    enum Kind { case todos, homework }
    @Environment(\.nuistAccent) private var themeAccent
    let kind: Kind
    let summary: WorkSummary
    let snapshot: ScheduleSnapshot
    let now: Date
    private var overdue: Bool {
        (kind == .todos ? summary.nextTodo?.deadline : summary.nextHomework?.deadline).map { $0 < now } == true
    }
    private var ink: Color {
        if overdue { return CampusTheme.examAccent }
        if kind == .homework, let assignment = summary.nextHomework {
            return CampusTheme.courseAccent(for: assignment.courseKey, in: snapshot)
        }
        return themeAccent
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: kind == .todos ? "calendar.badge.clock" : "book.closed")
                Text(kind == .todos ? "日程状态" : "作业登机牌").fontWeight(.semibold)
                Spacer(minLength: 0)
                if kind == .homework, let assignment = summary.nextHomework {
                    CourseIDBadge(text: assignment.number, small: true, ink: ink)
                }
            }.font(.system(size: 11)).foregroundStyle(ink)
            if kind == .todos { todoDetails } else { homeworkDetails }
            Spacer(minLength: 0)
            Rectangle().fill(CampusTheme.boardLine).frame(height: 1)
            HStack(spacing: kind == .todos ? 14 : 28) {
                metric(kind == .todos ? "待完成" : "待交", value: kind == .todos ? summary.pendingTodos : summary.pendingHomework)
                metric(kind == .todos ? "今天" : "24h 内", value: kind == .todos ? summary.todayTodos : summary.upcomingHomework)
                metric("逾期", value: kind == .todos ? summary.overdueTodos : summary.overdueHomework)
                Spacer(minLength: 0)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).frame(height: 240)
            .background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(ink.opacity(0.25)) }
    }
    @ViewBuilder private var todoDetails: some View {
        if let todo = summary.nextTodo {
            Text(overdue ? "优先处理 · 已逾期" : "下一项安排").font(.system(size: 10)).foregroundStyle(.secondary)
            Text(todo.title).font(.system(size: 22, weight: .semibold)).foregroundStyle(ink)
                .lineLimit(2).minimumScaleFactor(0.8)
            if let date = overdue ? todo.deadline : WorkSummary.date(for: todo) {
                Label((date == todo.deadline ? "截止 " : "安排 ") + date.formatted(.dateTime.month().day().hour().minute()), systemImage: "clock")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else { Text("时间自由安排").font(.system(size: 12)).foregroundStyle(.secondary) }
        } else {
            Text("今天，留些空白").font(.system(size: 22, weight: .semibold)).foregroundStyle(ink)
            Text("暂无待办，在下方添加新的日程。").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var homeworkDetails: some View {
        if let assignment = summary.nextHomework {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text((overdue ? "逾期作业 · " : "下一份待交 · ") + (snapshot.profiles.first { $0.id == assignment.courseKey }?.title ?? "作业"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Text(assignment.title).font(.system(size: 28, weight: .semibold)).foregroundStyle(ink)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    if let date = assignment.deadline {
                        Text("截止 " + date.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 12)).foregroundStyle(.secondary)
                    } else { Text("未设置截止时间").font(.system(size: 12)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !assignment.items.isEmpty {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(assignment.completedCount)/\(assignment.items.count)")
                            .font(.system(size: 26, weight: .medium, design: .monospaced)).foregroundStyle(ink)
                        Text("子项已完成").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text("作业已清空，轻装出发").font(.system(size: 27, weight: .semibold)).foregroundStyle(ink)
                .lineLimit(2).minimumScaleFactor(0.75)
            Text("有新的作业时，在下方选择科目添加。").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String, value: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(value)").font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(title == "逾期" && value > 0 ? CampusTheme.examAccent : CampusTheme.boardText)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
