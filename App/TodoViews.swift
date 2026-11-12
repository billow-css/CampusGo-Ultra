import SwiftUI

struct TodoListView: View {
    @Environment(\.nuistAccent) private var themeAccent
    @EnvironmentObject private var store: AppStore
    @State private var editing: TodoItem?
    @State private var showCompleted = false
    private var pending: [TodoItem] {
        store.snapshot.todos.filter { !$0.isCompleted }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.deadline != $1.deadline { return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            return $0.createdAt < $1.createdAt
        }
    }
    private var completed: [TodoItem] { store.snapshot.todos.filter(\.isCompleted).sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("个人日程").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(pending.count) 项").font(.caption).foregroundStyle(.secondary)
                Button { editing = TodoItem(title: "") } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("添加待办")
            }.padding(18)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if pending.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle").font(.system(size: 27)).foregroundStyle(themeAccent)
                            Text("给今天留一点安排").font(.callout)
                            Button("添加待办") { editing = TodoItem(title: "") }
                        }.frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    ForEach(pending) { todo in todoCard(todo) }
                    if !completed.isEmpty {
                        DisclosureGroup("已完成（\(completed.count)）", isExpanded: $showCompleted) {
                            VStack(spacing: 8) { ForEach(completed) { todo in todoCard(todo) } }.padding(.top, 8)
                        }.font(.caption).foregroundStyle(.secondary).padding(.top, 9)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 18)
            }
        }.background(Color.primary.opacity(0.025))
            .sheet(item: $editing) { todo in TodoEditor(todo: todo) { store.saveTodo($0) } }
    }

    private func todoCard(_ todo: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { store.toggleTodo(todo.id) } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(todo.isCompleted ? themeAccent : Color.secondary)
            }.buttonStyle(.plain).help(todo.isCompleted ? "恢复为未完成" : "标记完成")
            Button { editing = todo } label: {
                VStack(alignment: .leading, spacing: 7) {
                    if todo.isPinned { Label("置顶", systemImage: "pin.fill").font(.system(size: 10)).foregroundStyle(themeAccent) }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: todo.icon).foregroundStyle(themeAccent)
                        Text(todo.title).strikethrough(todo.isCompleted).font(.system(size: 13, weight: .medium))
                    }
                    if let scheduled = todo.scheduledAt {
                        Text("安排于 " + scheduled.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let deadline = todo.deadline {
                        Text("截止 " + deadline.formatted(.dateTime.month().day().hour().minute()))
                            .font(.system(size: 11)).foregroundStyle(deadline < Date() && !todo.isCompleted ? Color.orange : Color.secondary)
                    }
                    if todo.scheduledAt == nil && todo.deadline == nil { Text("无时间安排").font(.system(size: 11)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(13).background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.06)) }
            .contextMenu {
                Button("编辑") { editing = todo }
                Button(todo.isPinned ? "取消置顶" : "置顶") { var updated = todo; updated.isPinned.toggle(); store.saveTodo(updated) }
                Button("删除待办", role: .destructive) { store.deleteTodo(todo.id) }
            }
    }
}

struct TodoEditor: View {
    @Environment(\.nuistAccent) private var themeAccent
    @Environment(\.dismiss) private var dismiss
    @State var todo: TodoItem
    let onSave: (TodoItem) -> Void
    @State private var hasSchedule = false
    @State private var hasDeadline = false
    private let icons = ["checklist", "book", "flask", "pencil", "person.3", "flag", "figure.run", "cup.and.saucer", "laptopcomputer", "heart", "music.note", "star"]
    private var valid: Bool { !todo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("个人日程").font(.title3).fontWeight(.semibold)
            TextField("标题（必填）", text: $todo.title).textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                ForEach(icons, id: \.self) { icon in
                    Button { todo.icon = icon } label: {
                        Image(systemName: icon).frame(width: 23, height: 26)
                            .foregroundStyle(todo.icon == icon ? themeAccent : Color.secondary)
                            .background(todo.icon == icon ? themeAccent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).help(icon)
                }
            }
            Toggle("置顶", isOn: $todo.isPinned)
            Toggle("设置安排时间", isOn: $hasSchedule)
            if hasSchedule {
                SmartDatePicker(title: "安排时间", selection: Binding(get: { todo.scheduledAt ?? Date() }, set: { todo.scheduledAt = $0 }))
            }
            Toggle("设置截止时间（DDL）", isOn: $hasDeadline)
            if hasDeadline {
                SmartDatePicker(title: "截止时间", selection: Binding(get: { todo.deadline ?? Date() }, set: { todo.deadline = $0 }))
            }
            Text("有 DDL 的待办会显示在对应日期的课表顶部。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    if !hasSchedule { todo.scheduledAt = nil }
                    else if todo.scheduledAt == nil { todo.scheduledAt = Date() }
                    if !hasDeadline { todo.deadline = nil }
                    else if todo.deadline == nil { todo.deadline = Date() }
                    onSave(todo); dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(themeAccent).disabled(!valid)
            }
        }.padding(25).frame(width: 465).tint(themeAccent)
            .onAppear { hasSchedule = todo.scheduledAt != nil; hasDeadline = todo.deadline != nil }
    }
}
