import SwiftUI

/// A widget-sized boarding pass. Tomorrow's first class uses the same headline as today's next class.
struct WidgetBoard: View {
    let snapshot: ScheduleSnapshot
    let now: Date
    let compact: Bool
    private let state: ReminderState
    init(snapshot: ScheduleSnapshot, now: Date, compact: Bool) {
        self.snapshot = snapshot; self.now = now; self.compact = compact
        state = ReminderEngine.state(snapshot: snapshot, at: now)
    }
    var body: some View {
        let featured = state.course ?? state.tomorrow.first
        let exams = state.upcomingExams.filter { $0.id != featured?.id }
        let next = state.phase == .tomorrow ? Array(state.tomorrow.dropFirst()) : state.next.map { [$0] } ?? []
        return VStack(alignment: .leading, spacing: compact ? 5 : 9) {
            if let event = featured {
                headline(event)
                if !next.isEmpty && (!compact || exams.isEmpty) {
                    ForEach(Array(next.prefix(compact ? 1 : 2))) { following in
                        HStack(spacing: 6) {
                            Text(following.isExam ? "NEXT · 考试" : "NEXT").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(following.isExam ? CampusTheme.examBoard : CampusTheme.boardSecondary)
                            Text(following.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(ScheduleFormat.time(following.start)).font(.system(size: 10, design: .monospaced))
                        }
                    }
                    if !compact && next.count > 2 {
                        Text("另有 \(next.count - 2) 节，点击查看完整安排").font(.system(size: 9)).foregroundStyle(CampusTheme.boardSecondary)
                    }
                }
            } else {
                Text("CampusGo Ultra").font(.system(size: 11, weight: .semibold)).foregroundStyle(CampusTheme.accent)
                Text(state.phase == .finished ? "今天已收官" : "接下来，自由安排")
                    .font(.system(size: compact ? 23 : 28, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text("明天暂无课程安排").font(.system(size: 11)).foregroundStyle(CampusTheme.boardSecondary)
            }
            if !exams.isEmpty { examSummary(exams, featuredIsExam: featured?.isExam == true) }
            if !state.deadlines.isEmpty {
                ForEach(Array(state.deadlines.prefix(compact ? 1 : 2))) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.deadline < now ? "exclamationmark.circle" : "clock")
                        Text(item.displayTitle).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.deadline, format: .dateTime.month().day().hour().minute()).lineLimit(1).minimumScaleFactor(0.8)
                    }.font(.system(size: compact ? 9 : 10)).foregroundStyle(CampusTheme.warm)
                        .accessibilityLabel((item.deadline < now ? "已逾期 " : "即将截止 ") + item.displayTitle)
                }
            }
            if !compact { Spacer(minLength: 0) }
        }.foregroundStyle(CampusTheme.boardText).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func headline(_ event: CourseOccurrence) -> some View {
        let ink = event.isExam ? CampusTheme.examBoard : CampusTheme.accent
        let current = state.phase == .current
        let target = current ? event.end : event.start
        let status = current ? (event.isExam ? "正在考试" : "正在上课") :
            (state.phase == .tomorrow ? (event.isExam ? "明天 · 考试" : "明天 · 首课") : (event.isExam ? "下节 · 考试" : "下节课"))
        return VStack(alignment: .leading, spacing: compact ? 5 : 9) {
            HStack(spacing: 7) {
                if let profile = snapshot.profile(for: event) { CourseIDBadge(text: profile.shortID, small: true, ink: ink) }
                Text(status).font(.system(size: 10, weight: .semibold)).lineLimit(1).foregroundStyle(ink)
                Spacer(minLength: 0)
                if compact && target > now { timer(to: target, ink: ink, small: true) }
            }
            HStack(alignment: .center, spacing: 10) {
                Text(event.title).font(.system(size: compact ? 25 : 31, weight: .semibold))
                    .foregroundStyle(ink).lineLimit(compact ? 1 : 2).minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !compact && target > now {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(current ? (event.isExam ? "距结束" : "距下课") : (event.isExam ? "距开考" : "距上课"))
                            .font(.system(size: 9)).foregroundStyle(CampusTheme.boardSecondary)
                        timer(to: target, ink: ink, small: false)
                    }
                }
            }
            HStack(spacing: 8) {
                Text(ScheduleFormat.timeRange(event)).monospacedDigit().fixedSize()
                Text([event.location, snapshot.profile(for: event)?.teacher ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }.font(.system(size: compact ? 10 : 11)).foregroundStyle(CampusTheme.boardSecondary)
            if !compact {
                Rectangle().fill(CampusTheme.boardLine).frame(height: 1).padding(.top, 2)
            }
        }
    }
    private func timer(to target: Date, ink: Color, small: Bool) -> some View {
        Text(timerInterval: now...target, pauseTime: target, countsDown: true, showsHours: true)
            .font(.system(size: small ? 13 : 18, weight: .medium, design: .monospaced))
            .monospacedDigit().multilineTextAlignment(.trailing).foregroundStyle(ink)
            .frame(width: small ? 66 : 90, alignment: .trailing)
    }
    private func examSummary(_ exams: [CourseOccurrence], featuredIsExam: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(exams.prefix(compact ? 1 : 2))) { exam in
                HStack(spacing: 5) {
                    Image(systemName: "pencil.and.list.clipboard")
                    Text(exam.title).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(exam.start, format: .dateTime.month().day().hour().minute()).lineLimit(1)
                }.font(.system(size: compact ? 9 : 10))
            }
            if !compact || exams.count > 1 {
                Text(featuredIsExam ? "另有 \(exams.count) 场考试 · 7 天内" : "7 天内共 \(exams.count) 场考试")
                    .font(.system(size: 9)).opacity(0.85)
            }
        }.foregroundStyle(CampusTheme.examBoard).padding(compact ? 5 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CampusTheme.examTint, in: RoundedRectangle(cornerRadius: 6))
    }
}
