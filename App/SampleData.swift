import Foundation

enum SampleData {
    static func make(now: Date = Date()) -> ScheduleSnapshot {
        var snapshot = ScheduleSnapshot(now: now)
        let calendar = Calendar.current
        let monday = ScheduleFormat.monday(containing: now)
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: monday)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }
        let names = [("高等数学", "A302", "王老师"), ("大学英语", "B201", "李老师"), ("程序设计", "机房203", "陈老师"), ("大学物理", "A105", "")]
        let slots = [(0,0,8,0,9,40),(1,2,10,10,11,50),(2,0,8,0,9,40),(2,1,10,10,11,50),(2,2,13,45,15,25),(3,3,8,0,9,40),(3,1,10,10,11,50),(4,0,10,10,11,50)]
        for week in 0...1 {
            for (day, index, sh, sm, eh, em) in slots {
                let course = names[index]
                snapshot.occurrences.append(.init(id: UUID().uuidString, calendarID: "demo", title: course.0,
                    start: date(day + week * 7, sh, sm), end: date(day + week * 7, eh, em), location: course.1, notes: "示例课程"))
            }
        }
        snapshot.registerCourses(snapshot.occurrences)
        for index in snapshot.profiles.indices {
            snapshot.profiles[index].teacher = names.first { $0.0 == snapshot.profiles[index].title }?.2 ?? ""
        }
        let today = calendar.startOfDay(for: now)
        let due = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today)!
        snapshot.todos = [
            .init(title: "提交实验报告", icon: "flask", deadline: due, isPinned: true),
            .init(title: "图书馆借书", icon: "book"),
            .init(title: "准备小组汇报", icon: "person.3", deadline: date(8,20))
        ]
        snapshot.settings.calendarIDs = ["demo"]
        snapshot.syncedAt = now
        if let course = snapshot.profiles.first(where: { $0.title == "程序设计" }) {
            try? snapshot.upsertHomework(.init(courseKey: course.id, title: "第五周作业", notes: "完成后提交到课程平台",
                deadline: date(4, 23, 59), items: [
                    .init(title: "完成第一题", isCompleted: true),
                    .init(title: "完成第二题"), .init(title: "撰写实验报告")
                ]))
        }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: today)!
        if let event = snapshot.occurrences.sorted(by: { $0.start < $1.start }).first(where: { $0.end > now && $0.start < dayEnd }) {
            var exam = ExamRecord.marking(event)
            exam.title += " · 阶段考试"
            snapshot.upsertExam(exam)
        }
        let examDay = calendar.date(byAdding: .day, value: 3, to: today)!
        let examStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: examDay)!
        snapshot.upsertExam(.init(title: "高等数学期中考试", start: examStart, end: examStart.addingTimeInterval(7200),
            location: "教学楼 A302", notes: "携带学生证与考试文具", linkedCourseKey: snapshot.profiles.first { $0.title == "高等数学" }?.id))
        return snapshot
    }
}
