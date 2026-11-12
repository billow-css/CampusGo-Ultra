import SwiftUI
import EventKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.nuistAccent) private var themeAccent
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var draft = ScheduleSettings()
    @State private var selection = "calendars"
    @State private var saving = false
    @State private var subscriptionURL = ""
    @State private var importingFile = false

    private var periodsValid: Bool {
        draft.periods.allSatisfy { $0.startMinute >= 0 && $0.endMinute <= 1440 && $0.startMinute < $0.endMinute }
            && zip(draft.periods, draft.periods.dropFirst()).allSatisfy { $0.endMinute <= $1.startMinute }
    }
    private var valid: Bool { draft.semesterEnd >= draft.semesterStart && periodsValid && draft.reminderHours > 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.title3).fontWeight(.semibold)
                Spacer()
                if store.isDemo { Text("演示模式").font(.caption).foregroundStyle(.secondary) }
            }.padding(20)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionButton("外观与主题", icon: "paintpalette", value: "appearance")
                    sectionButton("窗口桌宠", icon: "pawprint", value: "pet")
                    sectionButton("日历来源", icon: "calendar", value: "calendars")
                    sectionButton("课程与老师", icon: "person.text.rectangle", value: "courses")
                    sectionButton("考试安排", icon: "pencil.and.list.clipboard", value: "exams")
                    sectionButton("桌面小组件", icon: "rectangle.on.rectangle", value: "widgets")
                    sectionButton("学期与提醒", icon: "clock", value: "semester")
                    sectionButton("节次时间", icon: "list.number", value: "periods")
                    Spacer(minLength: 0)
                }.padding(12).frame(width: 170).frame(maxHeight: .infinity)
                    .background(Color.primary.opacity(0.035))
                Divider()
                Group {
                    switch selection {
                    case "appearance": AppearanceSettingsView()
                    case "pet": WindowPetSettingsView()
                    case "courses": courseSettings
                    case "exams": ExamSettingsView()
                    case "widgets": WidgetPreviewView()
                    case "semester": semesterSettings
                    case "periods": periodSettings
                    default: calendarSettings
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider().padding(.top, 12)
            HStack {
                if !valid { Text("请检查学期日期与节次时间，节次不能重叠。").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(saving ? "正在保存…" : "保存设置") {
                    saving = true
                    Task { await store.applySettings(draft); saving = false }
                }.buttonStyle(.borderedProminent).tint(themeAccent).disabled(!valid || saving || store.isRefreshing)
            }.padding(18)
        }.tint(themeAccent)
            .onAppear { draft = store.snapshot.settings; subscriptionURL = store.snapshot.importedCalendar?.subscriptionURL ?? "" }
            .task { await store.reloadCalendarList() }
            .onChange(of: store.snapshot.settings.calendarIDs) { _, ids in draft.calendarIDs = ids }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    store.importCalendarFile(url)
                case .failure(let error): store.calendarMessage = "无法打开文件：\(error.localizedDescription)"
                }
            }
    }

    private func sectionButton(_ title: String, icon: String, value: String) -> some View {
        Button { selection = value } label: {
            Label(title, systemImage: icon).font(.system(size: 13, weight: selection == value ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 11).padding(.vertical, 11)
                .foregroundStyle(selection == value ? themeAccent : Color.primary)
                .background(selection == value ? themeAccent.opacity(0.13) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
    }

    private var calendarSettings: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("选择已添加到 macOS 日历中的学校课表。").font(.callout)
            Label(store.calendarAccessSummary, systemImage: store.calendarStatus == .fullAccess ? "checkmark.shield" : "lock")
                .font(.caption).foregroundStyle(.secondary)
            if store.calendarStatus != .fullAccess && !store.isDemo {
                Text("需要日历读取权限才能列出订阅。应用只读取你选择的日历。").font(.caption).foregroundStyle(.secondary)
                Button(store.isRequestingCalendarAccess ? "正在等待授权…" : "授权读取日历") { Task { await store.requestCalendarAccess() } }
                    .buttonStyle(.borderedProminent).tint(themeAccent)
                    .disabled(store.isRequestingCalendarAccess)
                if store.calendarStatus == .denied || store.calendarStatus == .restricted {
                    Button("打开系统日历权限设置") {
                        openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
            } else if store.isDemo {
                Label("当前使用示例课表，退出演示模式后可连接系统日历。", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else if store.calendars.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("已允许访问，暂未读到系统日历。").fontWeight(.medium)
                    Text("可先打开系统“日历”确认课表可见，再重新读取；也可以在下方直接粘贴学校订阅链接。").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                ForEach(store.calendars) { item in
                    Toggle(isOn: Binding(get: { draft.calendarIDs.contains(item.id) }, set: { selected in
                        if selected { if !draft.calendarIDs.contains(item.id) { draft.calendarIDs.append(item.id) } }
                        else { draft.calendarIDs.removeAll { $0 == item.id } }
                        if let imported = store.snapshot.importedCalendar { draft.calendarIDs.removeAll { $0 == imported.sourceID } }
                    })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                            Text(item.source + (item.isSubscribed ? " · 已订阅" : "")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.checkbox).padding(.vertical, 4)
                }
                }
            }
            if store.calendarStatus == .fullAccess && !store.isDemo {
                Button("重新读取系统日历") { Task { await store.reloadCalendarList() } }.disabled(store.isRefreshing)
            }
            Divider().padding(.vertical, 3)
            Text("直接连接课表订阅").font(.headline)
            Text("粘贴学校提供的日历链接，或导入 .ics 文件。此方式无需读取其他系统日历。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("https://… 或 webcal://…", text: $subscriptionURL).textFieldStyle(.roundedBorder)
            HStack {
                Button(store.isRefreshing ? "正在读取…" : "连接订阅") {
                    Task { await store.connectSubscription(subscriptionURL) }
                }.buttonStyle(.borderedProminent).tint(themeAccent)
                    .disabled(store.isDemo || store.isRefreshing || subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("导入 .ics 文件") { importingFile = true }.disabled(store.isDemo || store.isRefreshing)
            }
            if let imported = store.snapshot.importedCalendar {
                Label("已连接：\(imported.name) · \(store.snapshot.profiles.filter { Set(store.snapshot.occurrences.map(\.courseKey)).contains($0.id) }.count) 门课程",
                    systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(themeAccent)
            }
            if let message = store.calendarMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var courseSettings: some View {
        let activeKeys = Set(store.snapshot.schedule.map(\.courseKey))
        let profiles = store.snapshot.profiles.filter { activeKeys.contains($0.id) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 12) {
            Text("当前学期识别到 \(profiles.count) 门课程。老师选填，留空时自动隐藏。").font(.caption).foregroundStyle(.secondary)
            if profiles.isEmpty {
                ContentUnavailableView("尚未识别到课程", systemImage: "books.vertical", description: Text("选择日历并保存设置后，课程会自动出现在这里。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(profiles) { profile in
                            CourseProfileRow(profile: profile) { store.saveProfile($0) }
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(18)
    }

    private var semesterSettings: some View {
        Form {
            Section("课表范围") {
                DatePicker("学期开始", selection: $draft.semesterStart, displayedComponents: .date)
                DatePicker("学期结束", selection: $draft.semesterEnd, displayedComponents: .date)
                Text("只读取此范围的课程；切换学期会保留已填写的老师和课程编号。").font(.caption).foregroundStyle(.secondary)
            }
            Section("截止提醒") {
                Stepper("提前 \(draft.reminderHours) 小时显示提醒", value: $draft.reminderHours, in: 1...168)
                Text("逾期未完成的任务会持续显示，勾选完成后移除提醒。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var periodSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("节次与实际时间同时显示。初始时间按学校订阅中的常见时段设置，可自行修改。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($draft.periods) { $period in
                        HStack {
                            Text("第 \(period.number) 节").frame(width: 65, alignment: .leading)
                            DatePicker("开始", selection: minuteBinding($period.startMinute), displayedComponents: .hourAndMinute)
                            Text("—").foregroundStyle(.secondary)
                            DatePicker("结束", selection: minuteBinding($period.endMinute), displayedComponents: .hourAndMinute)
                        }
                    }
                }.padding(.trailing, 10)
            }
            HStack {
                Button("添加节次") {
                    let end = draft.periods.last?.endMinute ?? 480
                    guard end + 55 < 1440 else { return }
                    draft.periods.append(.init(number: draft.periods.count + 1, startMinute: end + 10, endMinute: end + 55))
                }
                Button("移除末节") { if draft.periods.count > 1 { draft.periods.removeLast() } }.disabled(draft.periods.count <= 1)
                Spacer()
                Button("恢复初始时间") { draft.periods = LessonPeriod.defaults }
            }
        }.padding(18)
    }

    private func minuteBinding(_ binding: Binding<Int>) -> Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: binding.wrappedValue / 60, minute: binding.wrappedValue % 60,
                second: 0, of: Date())!
        }, set: { binding.wrappedValue = ScheduleFormat.minuteOfDay($0) })
    }
}

private struct CourseProfileRow: View {
    let profile: CourseProfile
    let save: (CourseProfile) -> Void
    @State private var teacher = ""
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.title).fontWeight(.medium)
                Text("#" + profile.shortID).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            TextField("老师（选填）", text: $teacher).textFieldStyle(.roundedBorder).frame(width: 155).onSubmit(commit)
            Button("保存", action: commit).disabled(teacher == profile.teacher)
        }.padding(.vertical, 11)
            .onAppear { teacher = profile.teacher }
            .onChange(of: profile.teacher) { _, value in teacher = value }
    }
    private func commit() {
        var updated = profile
        updated.teacher = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        save(updated)
    }
}
