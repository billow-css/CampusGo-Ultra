import SwiftUI

struct HomeHeroCard: View {
    @Environment(\.nuistAccent) private var themeAccent
    let snapshot: ScheduleSnapshot
    let now: Date

    var body: some View {
        let state = ReminderEngine.state(snapshot: snapshot, at: now)
        let event = state.course ?? state.tomorrow.first
        return VStack(alignment: .leading, spacing: 24) {
            if let event {
                featured(event, phase: state.phase)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("今日已收官").font(.system(size: 12, weight: .medium)).foregroundStyle(CampusTheme.boardSecondary)
                        Text("接下来，自由安排").font(.system(size: 32, weight: .semibold)).foregroundStyle(CampusTheme.boardText)
                        Text("今天和明天暂无待上的课程，右侧的日程和作业随时可处理。")
                            .font(.system(size: 13)).foregroundStyle(CampusTheme.boardSecondary)
                    }
                    Spacer()
                    Image(systemName: "moon.stars").font(.system(size: 38, weight: .light)).foregroundStyle(themeAccent)
                }.padding(.vertical, 16)
            }
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            .background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(CampusTheme.boardLine) }
    }

    private func featured(_ event: CourseOccurrence, phase: ReminderPhase) -> some View {
        let ink = event.isExam ? CampusTheme.examBoard : themeAccent
        let current = phase == .current
        let label = current ? (event.isExam ? "正在考试" : "正在上课") :
            (phase == .tomorrow ? (event.isExam ? "明天 · 下一场考试" : "明天 · 第一节课") : (event.isExam ? "下一场考试" : "下一节课"))
        let target = current ? event.end : event.start
        return VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                Circle().fill(ink).frame(width: 6, height: 6)
                Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                if let profile = snapshot.profile(for: event) { CourseIDBadge(text: profile.shortID, small: true, ink: ink) }
                Spacer()
                Text(event.start, format: .dateTime.month().day().weekday()).font(.system(size: 12)).foregroundStyle(CampusTheme.boardSecondary)
            }
            HStack(alignment: .center, spacing: 24) {
                Text(event.title).font(.system(size: 43, weight: .semibold))
                    .foregroundStyle(ink).lineLimit(2).minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if target > now {
                    VStack(alignment: .trailing, spacing: 7) {
                        Text(current ? (event.isExam ? "距考试结束" : "距下课") : (event.isExam ? "距开考" : "距上课"))
                            .font(.system(size: 11)).foregroundStyle(CampusTheme.boardSecondary)
                        Text(timerInterval: now...target, pauseTime: target, countsDown: true, showsHours: true)
                            .font(.system(size: 29, weight: .medium, design: .monospaced))
                            .monospacedDigit().multilineTextAlignment(.trailing).foregroundStyle(ink)
                            .frame(width: 166, alignment: .trailing)
                    }.fixedSize(horizontal: true, vertical: false)
                }
            }
            Rectangle().fill(CampusTheme.boardLine).frame(height: 1)
            HStack(alignment: .top, spacing: 30) {
                detail(event.isExam ? "考试时间" : "上课时间", value: ScheduleFormat.timeRange(event))
                if !event.location.isEmpty { detail(event.isExam ? "考场" : "教室", value: event.location) }
                if let teacher = snapshot.profile(for: event)?.teacher, !teacher.isEmpty { detail("老师", value: teacher) }
                Spacer(minLength: 0)
                if event.isExam {
                    Label("考试", systemImage: "pencil.and.list.clipboard")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(CampusTheme.examTint, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func detail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11)).foregroundStyle(CampusTheme.boardSecondary)
            Text(value).font(.system(size: 17, weight: .medium)).foregroundStyle(CampusTheme.boardText)
                .lineLimit(2).textSelection(.enabled)
        }
    }
}
