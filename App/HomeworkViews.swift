import SwiftUI

struct HomeworkListView: View {
    var spacious = false
    @Environment(\.nuistAccent) private var themeAccent
    @EnvironmentObject private var store: AppStore
    @State private var courseFilter = ""
    @State private var editing: HomeworkAssignment?
    @State private var showCompleted = false

    private var subjects: [CourseProfile] {
        store.snapshot.profiles.filter { !$0.id.hasPrefix("manual-exams::") }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var filtered: [HomeworkAssignment] {
        store.snapshot.homeworkRecords.filter { courseFilter.isEmpty || $0.courseKey == courseFilter }
    }
    private var pending: [HomeworkAssignment] {
        filtered.filter { !$0.isCompleted }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.deadline != $1.deadline { return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            return $0.createdAt < $1.createdAt
        }
    }
    private var completed: [HomeworkAssignment] { filtered.filter(\.isCompleted).sorted { $0.createdAt > $1.createdAt } }

    private func addHomework() {
        guard let course = subjects.first(where: { $0.id == courseFilter }) ?? subjects.first else { return }
        editing = HomeworkAssignment(courseKey: course.id, title: "")
    }

    var body: some View {
        let assignments = pending
        let finished = completed
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("作业").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(assignments.count) 份待完成").font(.caption).foregroundStyle(.secondary)
                Button(action: addHomework) { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("添加作业").disabled(subjects.isEmpty)
            }.padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
            Picker("科目", selection: $courseFilter) {
                Text("全部科目").tag("")
                ForEach(subjects) { subject in Text(subject.title).tag(subject.id) }
            }.pickerStyle(.menu).padding(.horizontal, 14).padding(.bottom, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if assignments.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "book.closed").font(.system(size: 27)).foregroundStyle(themeAccent)
                            Text(subjects.isEmpty ? "先连接课表，识别科目" : "当前没有待完成作业").font(.callout)
                            if !subjects.isEmpty { Button("添加作业", action: addHomework) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    ForEach(subjects.filter { subject in assignments.contains { $0.courseKey == subject.id } }) { subject in
                        Text(subject.title).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CampusTheme.courseAccent(for: subject.id, in: store.snapshot)).padding(.top, 5)
                        LazyVGrid(columns: spacious ? [GridItem(.adaptive(minimum: 255), spacing: 12, alignment: .top)] : [GridItem(.flexible())], alignment: .leading, spacing: 12) {
                            ForEach(assignments.filter { $0.courseKey == subject.id }) { assignment in
                                HomeworkCard(homework: assignment) { editing = assignment }
                            }
                        }
                    }
                    if !finished.isEmpty {
                        DisclosureGroup("已完成（\(finished.count)）", isExpanded: $showCompleted) {
                            LazyVStack(spacing: 8) {
                                ForEach(finished) { assignment in
                                    HomeworkCard(homework: assignment) { editing = assignment }
                                }
                            }.padding(.top, 8)
                        }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 18)
            }
        }.sheet(item: $editing) { assignment in HomeworkEditor(homework: assignment).environmentObject(store) }
    }
}

struct HomeworkCard: View {
    @EnvironmentObject private var store: AppStore
    let homework: HomeworkAssignment
    let onEdit: () -> Void
    @State private var expanded = true

    var body: some View {
        let ink = CampusTheme.courseAccent(for: homework.courseKey, in: store.snapshot)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                CourseIDBadge(text: homework.number, small: true, ink: ink)
                if homework.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(ink) }
                Spacer(minLength: 0)
                Menu {
                    Button("编辑作业", action: onEdit)
                    Button(homework.isPinned ? "取消置顶" : "置顶") {
                        var updated = homework
                        updated.isPinned.toggle()
                        do { try store.saveHomework(updated) } catch { store.errorMessage = error.localizedDescription }
                    }
                    Button("删除作业", role: .destructive) { store.deleteHomework(homework.id) }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("作业操作")
            }
            HStack(alignment: .top, spacing: 8) {
                Button { store.toggleHomework(homework.id) } label: {
                    Image(systemName: homework.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18)).foregroundStyle(homework.isCompleted ? ink : Color.secondary)
                }.buttonStyle(.plain).help(homework.isCompleted ? "恢复整份作业" : "完成整份作业及所有子项")
                Button(action: onEdit) {
                    Text(homework.title).font(.system(size: 13, weight: .semibold))
                        .strikethrough(homework.isCompleted).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if let due = homework.deadline {
                Label("截止 " + due.formatted(.dateTime.month().day().hour().minute()), systemImage: "clock")
                    .font(.system(size: 11)).foregroundStyle(due < Date() && !homework.isCompleted ? Color.orange : Color.secondary)
            }
            if !homework.items.isEmpty {
                HStack(spacing: 8) {
                    ProgressView(value: Double(homework.completedCount), total: Double(homework.items.count)).tint(ink)
                    Button { expanded.toggle() } label: {
                        HStack(spacing: 4) {
                            Text("\(homework.completedCount)/\(homework.items.count)").monospacedDigit()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }.font(.system(size: 10))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help(expanded ? "折叠子作业" : "展开子作业")
                }
                if expanded {
                    ForEach(homework.items) { item in
                        Button { store.toggleHomeworkSubtask(item.id, in: homework.id) } label: {
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(item.isCompleted ? ink : Color.secondary)
                                Text(item.title).strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                                Spacer(minLength: 0)
                            }.font(.system(size: 12)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !homework.notes.isEmpty {
                Text(homework.notes).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(12).background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 10))
            .background(ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(ink.opacity(0.30), lineWidth: 1) }
            .contextMenu {
                Button("编辑作业", action: onEdit)
                Button("删除作业", role: .destructive) { store.deleteHomework(homework.id) }
            }
    }
}

struct HomeworkEditor: View {
    @Environment(\.nuistAccent) private var themeAccent
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var homework: HomeworkAssignment
    @State private var hasDeadline = false
    @State private var errorMessage: String?
    private var subjects: [CourseProfile] {
        store.snapshot.profiles.filter { !$0.id.hasPrefix("manual-exams::") }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var valid: Bool {
        !homework.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            subjects.contains { $0.id == homework.courseKey } &&
            homework.items.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(homework.number.isEmpty ? "添加作业" : "编辑作业").font(.title3).fontWeight(.semibold)
                Spacer()
                if !homework.number.isEmpty { CourseIDBadge(text: homework.number, small: true) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("科目", selection: $homework.courseKey) {
                        ForEach(subjects) { subject in Text(subject.title).tag(subject.id) }
                    }
                    TextField("作业标题（必填）", text: $homework.title).textFieldStyle(.roundedBorder)
                    HStack {
                        Toggle("置顶", isOn: $homework.isPinned)
                        Spacer()
                        if homework.number.isEmpty { Text("保存后分配 H 开头的五位编号").font(.caption).foregroundStyle(.secondary) }
                    }
                    Toggle("设置截止时间（DDL）", isOn: $hasDeadline)
                        .onChange(of: hasDeadline) { _, value in
                            if value && homework.deadline == nil { homework.deadline = Date().addingTimeInterval(86400) }
                        }
                    if hasDeadline {
                        SmartDatePicker(title: "截止时间", selection: Binding(get: { homework.deadline ?? Date() }, set: { homework.deadline = $0 }), nextClass: store.snapshot.schedule.first { $0.courseKey == homework.courseKey && $0.start > Date() }?.start)
                    }
                    Divider()
                    HStack {
                        Text("子作业条目").font(.headline)
                        Spacer()
                        Button { homework.items.append(.init(title: "")) } label: {
                            Label("添加子项", systemImage: "plus")
                        }.controlSize(.small)
                    }
                    if homework.items.isEmpty {
                        Text("简单作业可以直接勾选完成，也可以拆成多个子项。").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach($homework.items) { item in subtaskEditor(item) }
                    MultilineTextInput(text: $homework.notes, placeholder: "备注（可选）", height: 90)
                    Text("子项共用整份作业的截止时间；全部完成后，作业自动完成并退出截止提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 3)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    if !hasDeadline { homework.deadline = nil }
                    do { try store.saveHomework(homework); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!valid)
            }
        }.padding(24).frame(width: 500, height: 550).tint(themeAccent)
            .onAppear { hasDeadline = homework.deadline != nil }
            .alert("无法保存作业", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private func subtaskEditor(_ item: Binding<HomeworkSubtask>) -> some View {
        HStack(spacing: 8) {
            Toggle("完成", isOn: item.isCompleted).labelsHidden().toggleStyle(.checkbox)
            TextField("子作业标题", text: item.title).textFieldStyle(.roundedBorder)
            Button {
                let id = item.wrappedValue.id
                homework.items.removeAll { $0.id == id }
            } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help("移除子项")
        }
    }
}
