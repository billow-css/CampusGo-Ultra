import SwiftUI
import Combine

struct WeekCalendarView: View {
    @Environment(\.nuistAccent) private var themeAccent
    @EnvironmentObject private var store: AppStore
    @Binding var weekOffset: Int
    @State private var now = Date()
    private let calendar = Calendar.current
    private let axisWidth: CGFloat = 54
    private var monday: Date {
        calendar.date(byAdding: .day, value: weekOffset * 7, to: ScheduleFormat.monday(containing: now))!
    }
    var body: some View {
        let layout = WeekCalendarLayout(snapshot: store.snapshot, monday: monday, calendar: calendar)
        let days = layout.days
        let deadlines = layout.deadlines
        return VStack(spacing: 0) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(monday.formatted(.dateTime.month().day())) — \(days[6].formatted(.dateTime.month().day()))")
                        .font(.system(size: 16, weight: .semibold))
                    Text(monday.formatted(.dateTime.year())).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }.help("上一周")
                Button("本周") { weekOffset = 0 }
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }.help("下一周")
            }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal, 14).padding(.vertical, 10)
            HStack(spacing: 3) {
                Color.clear.frame(width: axisWidth, height: 1)
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    HStack(spacing: 5) {
                        Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][index]).font(.system(size: 11))
                        Text(day.formatted(.dateTime.day())).font(.system(size: 14, weight: .semibold))
                    }.foregroundStyle(calendar.isDate(day, inSameDayAs: now) ? themeAccent : Color.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(calendar.isDate(day, inSameDayAs: now) ? themeAccent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                }
            }.padding(.horizontal, 8).padding(.bottom, 5)
            if !deadlines.isEmpty {
            HStack(alignment: .top, spacing: 3) {
                Text("DDL").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .frame(width: axisWidth, alignment: .center).padding(.top, 4)
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(deadlines.filter { calendar.isDate($0.deadline, inSameDayAs: day) }) { task in
                            let ink = task.courseKey.map { CampusTheme.courseAccent(for: $0, in: store.snapshot) } ?? Color(nsColor: .systemOrange)
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: task.icon)
                                Text("\(ScheduleFormat.time(task.deadline)) \(task.displayTitle)").lineLimit(2)
                            }.font(.system(size: 10)).foregroundStyle(ink)
                                .padding(4).frame(maxWidth: .infinity, alignment: .leading)
                                .background(ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                                .help(task.displayTitle + " · " + task.deadline.formatted())
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }.padding(.horizontal, 8).padding(.bottom, 6)
            }
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 3) {
                    timeAxis(layout).frame(width: axisWidth)
                    ForEach(days, id: \.self) { day in dayColumn(day, layout: layout) }
                }.padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 7)
            }
            if layout.events.isEmpty {
                Text(store.snapshot.settings.calendarIDs.isEmpty ? "在设置中选择学校日历后，这里将显示课程。" : "本周暂无课程；也可检查设置中的学期范围。")
                    .font(.caption).foregroundStyle(.secondary).padding(10)
            }
        }.onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private func timeAxis(_ layout: WeekCalendarLayout) -> some View {
        let position: (Int) -> CGFloat = { CGFloat(layout.scale.position(for: $0)) }
        let timelineHeight = CGFloat(layout.scale.height)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: axisWidth, height: timelineHeight)
            ForEach(store.snapshot.settings.periods.filter { $0.startMinute >= layout.startMinute && $0.startMinute < layout.endMinute }) { period in
                VStack(alignment: .trailing, spacing: 1) {
                    Text("第 \(period.number) 节").font(.system(size: 10, weight: .medium))
                    Text(ScheduleFormat.minute(period.startMinute)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }.frame(width: axisWidth - 8, alignment: .trailing)
                    .offset(y: position(period.startMinute))
            }
        }.frame(height: timelineHeight)
    }

    private func dayColumn(_ day: Date, layout: WeekCalendarLayout) -> some View {
        let position: (Int) -> CGFloat = { CGFloat(layout.scale.position(for: $0)) }
        let timelineHeight = CGFloat(layout.scale.height)
        let startMinute = layout.startMinute
        let endMinute = layout.endMinute
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
        let placements = layout.placements[day] ?? []
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: geometry.size.width, height: timelineHeight)
                if calendar.isDate(day, inSameDayAs: now) { themeAccent.opacity(0.045) }
                ForEach(Array(stride(from: startMinute, to: endMinute, by: 60)), id: \.self) { minute in
                    Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5)
                        .offset(y: position(minute))
                }
                ForEach(placements) { placed in
                    let event = placed.event
                    let start = event.start < day ? 0 : ScheduleFormat.minuteOfDay(event.start)
                    let end = event.end >= dayEnd ? 1440 : ScheduleFormat.minuteOfDay(event.end)
                    let width = max(20, geometry.size.width / CGFloat(placed.lanes) - 3)
                    CourseCard(event: event, now: now, small: end - start < 65)
                        .frame(width: width, height: max(25, position(end) - position(start) - 2), alignment: .topLeading)
                        .offset(x: CGFloat(placed.lane) * (geometry.size.width / CGFloat(placed.lanes)),
                            y: position(max(startMinute, start)))
                }
                if calendar.isDate(day, inSameDayAs: now) {
                    let minute = ScheduleFormat.minuteOfDay(now)
                    if minute >= startMinute && minute < endMinute {
                        Rectangle().fill(themeAccent).frame(height: 1.5)
                            .overlay(alignment: .leading) { Circle().fill(themeAccent).frame(width: 5, height: 5) }
                            .offset(y: position(minute)).allowsHitTesting(false)
                    }
                }
            }.frame(height: timelineHeight).clipShape(RoundedRectangle(cornerRadius: 6))
        }.frame(maxWidth: .infinity).frame(height: timelineHeight)
    }
}

struct CourseCard: View {
    @EnvironmentObject private var store: AppStore
    let event: CourseOccurrence
    let now: Date
    var small = false
    @State private var showingDetails = false
    @State private var editingExam: ExamRecord?
    private var active: Bool { event.start <= now && now < event.end }
    private var courseColor: Color { CampusTheme.courseAccent(for: event, in: store.snapshot) }
    var body: some View {
        Button { showingDetails = true } label: {
            VStack(alignment: .leading, spacing: small ? 1 : 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if event.isExam {
                        Text("考试").font(.system(size: 9, weight: .bold)).foregroundStyle(CampusTheme.badgeText)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(CampusTheme.examAccent, in: RoundedRectangle(cornerRadius: 2))
                    }
                    Text(event.title).font(.system(size: small ? 11 : 12, weight: .semibold)).lineLimit(small ? 1 : 2)
                }
                Text(ScheduleFormat.timeRange(event)).font(.system(size: 10, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
                if small {
                    Text([event.location, store.snapshot.profile(for: event)?.teacher ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text(event.location).font(.system(size: 11)).lineLimit(1)
                    if let teacher = store.snapshot.profile(for: event)?.teacher, !teacher.isEmpty {
                        Text(teacher).font(.system(size: 11)).lineLimit(1)
                    }
                }
            }.foregroundStyle(event.isExam ? CampusTheme.examAccent : courseColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 5).padding(.vertical, small ? 2 : 4)
                .background(event.isExam ? CampusTheme.examAccent.opacity(active ? 0.18 : 0.09) : courseColor.opacity(active ? 0.30 : 0.18))
                .overlay(alignment: .leading) {
                    if !event.isExam { Rectangle().fill(courseColor).frame(width: 3) }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: event.isExam ? 3 : 6)
                        .strokeBorder(event.isExam ? CampusTheme.examAccent.opacity(0.65) : courseColor.opacity(active ? 0.9 : 0.25), lineWidth: active ? 1.5 : 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: event.isExam ? 3 : 6))
        }.buttonStyle(.plain)
            .help([event.title, ScheduleFormat.timeRange(event), event.location, store.snapshot.profile(for: event)?.teacher ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            .popover(isPresented: $showingDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let profile = store.snapshot.profile(for: event) { CourseIDBadge(text: profile.shortID, ink: event.isExam ? CampusTheme.examBoard : courseColor) }
                        if event.isExam { Label("考试", systemImage: "pencil.and.list.clipboard").font(.caption).foregroundStyle(CampusTheme.examAccent) }
                    }
                    Text(event.title).font(.title3).fontWeight(.semibold)
                    Text(ScheduleFormat.periodLabel(event, periods: store.snapshot.settings.periods))
                    Label(event.start.formatted(.dateTime.month().day()) + " · " + ScheduleFormat.timeRange(event), systemImage: "clock")
                    if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse") }
                    if let teacher = store.snapshot.profile(for: event)?.teacher, !teacher.isEmpty { Label(teacher, systemImage: "person") }
                    if !event.notes.isEmpty { Divider(); Text(event.notes).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    Divider()
                    Button(event.isExam ? "编辑考试" : "将本次课程标记为考试") {
                        showingDetails = false
                        editingExam = store.examDraft(for: event)
                    }.buttonStyle(.borderedProminent).tint(CampusTheme.examAccent)
                    if let id = event.examID {
                        Button(store.snapshot.examRecords.first { $0.id == id }?.sourceOccurrenceID == nil ? "删除考试" : "取消考试标记，恢复原课次", role: .destructive) {
                            showingDetails = false; store.deleteExam(id)
                        }.font(.caption)
                    }
                }.padding(20).frame(width: 330, alignment: .leading)
            }
            .contextMenu {
                Button(event.isExam ? "编辑考试" : "标记为考试") { editingExam = store.examDraft(for: event) }
                if let id = event.examID {
                    Button(store.snapshot.examRecords.first { $0.id == id }?.sourceOccurrenceID == nil ? "删除考试" : "取消考试标记，恢复原课次", role: .destructive) { store.deleteExam(id) }
                }
            }
            .sheet(item: $editingExam) { exam in ExamEditor(exam: exam) { store.saveExam($0) }.environmentObject(store) }
    }
}
