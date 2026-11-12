import SwiftUI
import AppKit

enum CampusTheme {
    // Keep orange reserved for exams. Random course IDs seed a stable palette choice.
    private static let coursePalette: [Color] = [
        0x2367C9, 0x4F54C6, 0x7748B8, 0xA345A6, 0xBC3D75, 0xB84250,
        0x167F82, 0x168366, 0x3D7E38, 0x647924, 0x256B98, 0x5866AD
    ].map { hex in
        Color(nsColor: NSColor(name: "Course-\(hex)") { appearance in
            let red = Double((hex >> 16) & 255) / 255
            let green = Double((hex >> 8) & 255) / 255
            let blue = Double(hex & 255) / 255
            let lift = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.42 : 0.0
            return NSColor(srgbRed: red + (1 - red) * lift,
                green: green + (1 - green) * lift, blue: blue + (1 - blue) * lift, alpha: 1)
        })
    }

    static func courseAccent(for event: CourseOccurrence, in snapshot: ScheduleSnapshot) -> Color {
        courseAccent(for: event.courseKey, in: snapshot)
    }

    static func courseAccent(for courseKey: String, in snapshot: ScheduleSnapshot) -> Color {
        func seed(_ key: String) -> Int {
            let hash = key.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            return Int(hash % UInt64(coursePalette.count))
        }
        // Profiles retain insertion order. Avoid repeats until the palette is exhausted;
        // adding a new subject does not recolor any existing subjects.
        var used = Set<Int>()
        for profile in snapshot.profiles {
            if used.count == coursePalette.count { used.removeAll() }
            var index = seed(profile.shortID)
            while used.contains(index) { index = (index + 1) % coursePalette.count }
            used.insert(index)
            if profile.id == courseKey { return coursePalette[index] }
        }
        return coursePalette[seed(courseKey)]
    }

    // NUIST VI manual A27: 南信大蓝, RGB 0 / 103 / 156 (#00679C).
    static let brand = Color(red: 0, green: 103.0 / 255, blue: 156.0 / 255)
    static let accent = Color(nsColor: NSColor(name: "NUISTAccent") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // A lighter interface tint keeps blue text readable on dark surfaces.
            return NSColor(srgbRed: 101.0 / 255, green: 170.0 / 255, blue: 221.0 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 0, green: 103.0 / 255, blue: 156.0 / 255, alpha: 1)
    })
    private static func adaptive(_ name: String, light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: name) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let board = adaptive("CardSurface", light: 0xFFFFFF, dark: 0x232832)
    static let boardText = adaptive("CardText", light: 0x1D2B3A, dark: 0xE7ECF3)
    static let boardSecondary = adaptive("CardSecondary", light: 0x647181, dark: 0xA4AFBD)
    static let boardLine = adaptive("CardLine", light: 0x000000, dark: 0xFFFFFF).opacity(0.10)
    static let badgeText = adaptive("BadgeText", light: 0xFFFFFF, dark: 0x17212D)
    static let warm = adaptive("DeadlineText", light: 0x97640F, dark: 0xE9B45E)
    static let examAccent = Color(nsColor: NSColor(name: "NUISTExam") { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 1, green: 0.70, blue: 0.36, alpha: 1)
        }
        return NSColor(srgbRed: 184.0 / 255, green: 94.0 / 255, blue: 18.0 / 255, alpha: 1)
    })
    static let examBoard = examAccent
    static let examTint = adaptive("ExamSurface", light: 0xFFF7ED, dark: 0x382B22)
    static func reminderSurface(_ snapshot: ScheduleSnapshot?, at now: Date) -> Color {
        board
    }
}

private struct NuistAccentKey: EnvironmentKey {
    static let defaultValue = CampusTheme.accent
}
extension EnvironmentValues {
    var nuistAccent: Color {
        get { self[NuistAccentKey.self] }
        set { self[NuistAccentKey.self] = newValue }
    }
}

struct CourseIDBadge: View {
    let text: String
    var small = false
    var ink = CampusTheme.accent
    var body: some View {
        Text("#" + text).font(.system(size: small ? 11 : 14, weight: .semibold, design: .monospaced))
            .tracking(1.4).foregroundStyle(CampusTheme.badgeText).lineLimit(1).fixedSize()
            .padding(.horizontal, small ? 5 : 8).padding(.vertical, small ? 2 : 4)
            .background(ink, in: RoundedRectangle(cornerRadius: 3))
    }
}

struct ReminderBoard: View {
    @Environment(\.nuistAccent) private var themeAccent
    let snapshot: ScheduleSnapshot
    let now: Date
    var compact = false
    var widget = false
    private let state: ReminderState

    init(snapshot: ScheduleSnapshot, now: Date, compact: Bool = false, widget: Bool = false) {
        self.snapshot = snapshot
        self.now = now
        self.compact = compact
        self.widget = widget
        self.state = ReminderEngine.state(snapshot: snapshot, at: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 14) {
            if let event = state.course {
                if event.isExam {
                    featuredExam(event)
                } else {
                HStack(alignment: .center, spacing: 12) {
                    if let profile = snapshot.profile(for: event) { CourseIDBadge(text: profile.shortID, small: compact, ink: themeAccent) }
                    Text(state.phase == .current ? "正在上课" : "下节课")
                        .font(.system(size: compact ? 11 : 12)).tracking(2).foregroundStyle(CampusTheme.boardSecondary)
                    Spacer(minLength: 0)
                    if state.phase == .upcoming {
                        countdown(to: event, small: compact || widget)
                    }
                }
                HStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .leading, spacing: compact ? 7 : 10) {
                        Text(event.title).font(.system(size: compact ? 24 : 34, weight: .medium))
                            .lineLimit(compact && !state.upcomingExams.isEmpty ? 1 : 2).minimumScaleFactor(0.65).foregroundStyle(themeAccent)
                        courseDetails(event)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !compact && !widget, let next = state.next {
                        Rectangle().fill(CampusTheme.boardLine).frame(width: 1, height: 65)
                        nextCourse(next).frame(width: 210, alignment: .leading)
                    }
                }
                }
                if (compact || widget) && !(compact && !state.upcomingExams.isEmpty), let next = state.next {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(next.isExam ? "NEXT · 考试" : "NEXT").tracking(1).foregroundStyle(next.isExam ? CampusTheme.examBoard : CampusTheme.boardSecondary)
                        Text(next.title).lineLimit(1)
                        if state.phase == .current {
                            countdown(to: next, small: true, includesLabel: false)
                        } else {
                            Text(ScheduleFormat.time(next.start)).foregroundStyle(CampusTheme.boardSecondary)
                        }
                    }.font(.system(size: compact ? 11 : 13))
                }
            } else if state.phase == .tomorrow {
                if widget {
                    VStack(alignment: .leading, spacing: 5) {
                        tomorrowHeading
                        if let next = state.nextToStart { countdown(to: next, small: true) }
                    }
                } else {
                    HStack {
                        tomorrowHeading
                        Spacer()
                        if let next = state.nextToStart { countdown(to: next, small: true) }
                    }
                }
                VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                    ForEach(state.tomorrow) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: compact ? 6 : 13) {
                                if let profile = snapshot.profile(for: event) { CourseIDBadge(text: profile.shortID, small: true, ink: event.isExam ? CampusTheme.examBoard : themeAccent) }
                                Text(ScheduleFormat.timeRange(event)).monospacedDigit()
                                Text((event.isExam ? "考试 · " : "") + event.title).lineLimit(1).minimumScaleFactor(0.65)
                                    .foregroundStyle(event.isExam ? CampusTheme.examBoard : CampusTheme.boardText)
                                if !widget { tomorrowDetails(event) }
                            }
                            if widget && !compact { tomorrowDetails(event) }
                        }.font(.system(size: compact ? 11 : 13))
                    }
                }
            } else {
                Text(state.phase == .finished ? "今天的课程已结束" : "今天暂无课程")
                    .font(.system(size: compact ? 22 : 28, weight: .medium))
                Text("明天暂无课程安排").font(.system(size: 12)).foregroundStyle(CampusTheme.boardSecondary)
            }
            if !state.upcomingExams.isEmpty {
                ExamNotice(exams: state.upcomingExams, compact: compact, widget: widget)
            }
            if !state.deadlines.isEmpty {
                Rectangle().fill(CampusTheme.boardLine).frame(height: 1)
                ForEach(Array(state.deadlines.prefix(compact ? 1 : 3))) { task in
                    HStack(spacing: 7) {
                        Image(systemName: task.deadline < now ? "exclamationmark.circle" : "clock")
                        Text(task.deadline < now ? "已逾期" : "即将截止")
                        Text(task.displayTitle).lineLimit(1)
                        Text(task.deadline, format: .dateTime.month().day().hour().minute()).lineLimit(1)
                    }.font(.system(size: compact ? 11 : 12)).foregroundStyle(CampusTheme.warm)
                }
                if state.deadlines.count > (compact ? 1 : 3) {
                    Text("另有 \(state.deadlines.count - (compact ? 1 : 3)) 项截止提醒")
                        .font(.system(size: 11)).foregroundStyle(CampusTheme.warm.opacity(0.8))
                }
            }
        }.foregroundStyle(CampusTheme.boardText).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func courseDetails(_ event: CourseOccurrence) -> some View {
        HStack(spacing: compact ? 9 : 17) {
            Text(ScheduleFormat.timeRange(event)).monospacedDigit()
            if !event.location.isEmpty { Text(event.location).lineLimit(1).minimumScaleFactor(0.7) }
            if let teacher = snapshot.profile(for: event)?.teacher, !teacher.isEmpty {
                Text(teacher).lineLimit(1)
            }
        }.font(.system(size: compact ? 11 : 13))
    }

    private var tomorrowHeading: some View {
        Text("今日课程已结束 · 明天的课程").font(.system(size: compact ? 11 : 12))
            .tracking(1).foregroundStyle(CampusTheme.boardSecondary)
    }

    @ViewBuilder
    private func countdown(to event: CourseOccurrence, small: Bool, includesLabel: Bool = true) -> some View {
        if event.start > now {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "hourglass").accessibilityHidden(true)
                    .font(.system(size: small ? 10 : 12)).foregroundStyle(CampusTheme.boardSecondary)
                if includesLabel {
                    Text(event.isExam ? "距开考" : "距上课").font(.system(size: small ? 11 : 12)).foregroundStyle(CampusTheme.boardSecondary)
                }
                // Bounded system timers update inside WidgetKit without requesting per-second timelines.
                Text(timerInterval: now...event.start, pauseTime: event.start, countsDown: true, showsHours: true)
                    .font(.system(size: small ? 14 : 21, weight: .medium, design: .monospaced))
                    .monospacedDigit().multilineTextAlignment(.trailing)
                    .frame(width: small ? 72 : 104, alignment: .trailing)
                    .accessibilityHint("距离\(event.title)\(event.isExam ? "开考" : "上课")的剩余时间")
            }.foregroundStyle(event.isExam ? CampusTheme.examBoard : themeAccent).fixedSize(horizontal: true, vertical: false)
        }
    }

    private func tomorrowDetails(_ event: CourseOccurrence) -> some View {
        HStack(spacing: 10) {
            if !event.location.isEmpty { Text(event.location) }
            if let teacher = snapshot.profile(for: event)?.teacher, !teacher.isEmpty { Text(teacher) }
        }.foregroundStyle(CampusTheme.boardSecondary)
    }

    private func nextCourse(_ event: CourseOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.isExam ? "NEXT · 考试" : "NEXT").font(.system(size: 11)).tracking(1).foregroundStyle(event.isExam ? CampusTheme.examBoard : CampusTheme.boardSecondary)
                Spacer(minLength: 4)
                if state.phase == .current { countdown(to: event, small: true, includesLabel: false) }
            }
            Text(event.title).font(.system(size: 17, weight: .medium)).lineLimit(2).foregroundStyle(event.isExam ? CampusTheme.examBoard : CampusTheme.boardText)
            Text([ScheduleFormat.timeRange(event), event.location].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 12)).foregroundStyle(CampusTheme.boardSecondary)
        }
    }

    private func featuredExam(_ event: CourseOccurrence) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            HStack(spacing: compact ? 7 : 12) {
                Text(widget ? (state.phase == .current ? "正在考试" : "下节 · 考试") : "EXAM / 考试")
                    .font(.system(size: compact || widget ? 10 : 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(CampusTheme.badgeText).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(CampusTheme.examBoard, in: RoundedRectangle(cornerRadius: 2))
                    .fixedSize()
                if let profile = snapshot.profile(for: event) { CourseIDBadge(text: profile.shortID, small: true, ink: CampusTheme.examBoard) }
                if !widget {
                    Text(state.phase == .current ? "正在考试" : "下节 · 考试").font(.system(size: compact ? 10 : 12)).foregroundStyle(CampusTheme.examBoard)
                }
                Spacer(minLength: 0)
                if state.phase == .upcoming { countdown(to: event, small: compact || widget, includesLabel: !compact && !widget) }
            }
            HStack(spacing: 16) {
                if !compact {
                    VStack(spacing: 1) {
                        Text(String(Calendar.current.component(.day, from: event.start))).font(.system(size: 27, weight: .bold, design: .rounded)).lineLimit(1)
                        Text(event.start, format: .dateTime.month()).font(.system(size: 11))
                    }.foregroundStyle(CampusTheme.examBoard).frame(width: 51).padding(.vertical, 6)
                        .background(CampusTheme.examTint, in: RoundedRectangle(cornerRadius: 4))
                }
                VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                    Text(event.title).font(.system(size: compact ? 23 : 28, weight: .semibold))
                        .lineLimit(compact ? 1 : 2).minimumScaleFactor(0.65).foregroundStyle(CampusTheme.examBoard)
                    courseDetails(event)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !compact && !widget, let next = state.next { nextCourse(next).frame(width: 210, alignment: .leading) }
            }
        }
    }
}

struct ExamNotice: View {
    let exams: [CourseOccurrence]
    var compact = false
    var widget = false
    private var limit: Int { compact ? 1 : (widget ? 2 : 6) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if compact, let exam = exams.first {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("7天内 · \(exams.count)场考试").font(.system(size: 10, weight: .semibold)).foregroundStyle(CampusTheme.examBoard)
                        Text(exam.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    }
                    HStack(spacing: 7) {
                        Text(exam.start, format: .dateTime.month().day().hour().minute()).monospacedDigit()
                        if !exam.location.isEmpty { Text(exam.location).lineLimit(1) }
                    }.font(.system(size: 10)).foregroundStyle(CampusTheme.boardSecondary)
                }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CampusTheme.examTint, in: RoundedRectangle(cornerRadius: 5))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: widget ? 140 : 220, maximum: widget ? 180 : 280), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                    ForEach(Array(exams.prefix(limit))) { exam in examTile(exam) }
                }
                if exams.count > limit {
                    Text("另有 \(exams.count - limit) 场考试，可在考试安排中查看。")
                        .font(.system(size: 10)).foregroundStyle(CampusTheme.boardSecondary)
                }
            }
        }.foregroundStyle(CampusTheme.boardText).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func examTile(_ exam: CourseOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "pencil.and.list.clipboard")
                Text("考试 · 7天内").fontWeight(.semibold)
                Spacer(minLength: 0)
                Text(exam.start, format: .dateTime.month().day()).foregroundStyle(CampusTheme.boardSecondary)
            }.font(.system(size: 10)).foregroundStyle(CampusTheme.examBoard)
            Text(exam.title).font(.system(size: widget ? 12 : 13, weight: .semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Text(ScheduleFormat.time(exam.start)).monospacedDigit().foregroundStyle(CampusTheme.examBoard)
                if !exam.location.isEmpty { Text(exam.location).foregroundStyle(CampusTheme.boardSecondary).lineLimit(1) }
            }.font(.system(size: 11))
        }.padding(10).frame(height: 88, alignment: .topLeading)
            .background(CampusTheme.examTint, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(CampusTheme.examBoard.opacity(0.16), lineWidth: 1) }
    }
}
