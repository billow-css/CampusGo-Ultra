import SwiftUI

struct ExamEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var exam: ExamRecord
    let onSave: (ExamRecord) -> Void
    private var valid: Bool {
        !exam.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && exam.end > exam.start
    }
    private var courses: [CourseProfile] {
        let keys = Set(store.snapshot.schedule.map(\.courseKey))
        return store.snapshot.profiles.filter { keys.contains($0.id) || $0.id == exam.linkedCourseKey }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("考试安排", systemImage: "pencil.and.list.clipboard").font(.title3).fontWeight(.semibold)
                .foregroundStyle(CampusTheme.examAccent)
            if exam.sourceOccurrenceID != nil {
                Text("将这一课次标记为考试，其他课次保持正常上课。取消标记可恢复原课次。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("关联课程", selection: Binding(get: { exam.linkedCourseKey ?? "" }, set: { key in
                    let previousTitle = courses.first { $0.id == exam.linkedCourseKey }?.title
                    exam.linkedCourseKey = key.isEmpty ? nil : key
                    if exam.title.isEmpty || exam.title == previousTitle,
                        let course = courses.first(where: { $0.id == key }) { exam.title = course.title }
                })) {
                    Text("独立考试").tag("")
                    ForEach(courses) { course in Text(course.title).tag(course.id) }
                }
            }
            TextField("考试科目 / 名称（必填）", text: $exam.title).textFieldStyle(.roundedBorder)
            SmartDatePicker(title: "开始时间", selection: $exam.start)
            SmartDatePicker(title: "结束时间", selection: $exam.end)
            if exam.end <= exam.start { Text("结束时间必须晚于开始时间。").font(.caption).foregroundStyle(CampusTheme.examAccent) }
            TextField("考场 / 地点（可稍后补充）", text: $exam.location).textFieldStyle(.roundedBorder)
            Text("考试备注").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $exam.notes).font(.callout).frame(height: 75)
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)) }
            Text("提前 7 天进入考试提醒；临近开考时显示“考试”标识和开考倒计时。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存考试") { onSave(exam); dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .tint(CampusTheme.examAccent).disabled(!valid)
            }
        }.padding(24).frame(width: 490).tint(CampusTheme.examAccent)
            .onChange(of: exam.start) { previous, updated in
                let duration = max(60, exam.end.timeIntervalSince(previous))
                exam.end = updated.addingTimeInterval(duration)
            }
    }
}

struct ExamSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: ExamRecord?
    @State private var showPast = false
    private var future: [ExamRecord] { store.snapshot.examRecords.filter { $0.end >= Date() }.sorted { $0.start < $1.start } }
    private var past: [ExamRecord] { store.snapshot.examRecords.filter { $0.end < Date() }.sorted { $0.start > $1.start } }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("考试安排").font(.headline)
                Spacer()
                Button {
                    let start = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                    editing = .init(title: "", start: start, end: start.addingTimeInterval(7200))
                } label: { Label("添加考试", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(CampusTheme.examAccent)
            }
            Text("可独立添加考试，也可在课表中右键某一课次 → 标记为考试。未来 7 天的考试会显示在提醒区下方。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if future.isEmpty {
                        Text("暂无即将到来的考试").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 35)
                    }
                    ForEach(future) { exam in examRow(exam) }
                    if !past.isEmpty {
                        DisclosureGroup("已结束（\(past.count)）", isExpanded: $showPast) {
                            VStack(spacing: 8) { ForEach(past) { exam in examRow(exam) } }.padding(.top, 8)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(20)
            .sheet(item: $editing) { exam in ExamEditor(exam: exam) { store.saveExam($0) }.environmentObject(store) }
    }

    private func examRow(_ exam: ExamRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pencil.and.list.clipboard").foregroundStyle(CampusTheme.examAccent).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(exam.title).font(.system(size: 13, weight: .semibold))
                Text(exam.start.formatted(.dateTime.month().day().hour().minute()) + "–" + ScheduleFormat.time(exam.end))
                    .font(.caption).foregroundStyle(.secondary)
                if !exam.location.isEmpty { Text(exam.location).font(.caption).foregroundStyle(.secondary) }
                Text(exam.sourceOccurrenceID == nil ? "手动添加" : "课程标记").font(.system(size: 10)).foregroundStyle(CampusTheme.examAccent)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("编辑") { editing = exam }.controlSize(.small)
            Menu {
                Button(exam.sourceOccurrenceID == nil ? "删除考试" : "取消考试标记，恢复原课次", role: .destructive) { store.deleteExam(exam.id) }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 20)
        }.padding(11).background(CampusTheme.examAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
    }
}
