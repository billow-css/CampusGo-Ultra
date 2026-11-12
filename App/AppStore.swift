import SwiftUI
import Combine
import EventKit
import WidgetKit

struct CalendarChoice: Identifiable {
    let id: String
    let title: String
    let source: String
    let isSubscribed: Bool
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: ScheduleSnapshot
    @Published private(set) var calendars: [CalendarChoice] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRequestingCalendarAccess = false
    @Published var calendarMessage: String?
    @Published var errorMessage: String?
    @Published var requestingBackupImport = false
    @Published private(set) var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var isDemo: Bool
    private let calendarReader = CalendarReader()
    private var repository: SharedRepository?
    private var calendarObserver: NSObjectProtocol?
    var isSharingEnabled: Bool { repository?.isShared == true }
    var calendarAccessSummary: String {
        switch calendarStatus {
        case .fullAccess: return "系统日历已授权 · 读取到 \(calendars.count) 个日历"
        case .writeOnly: return "当前仅允许写入，需要允许完整访问才能读取课表"
        case .denied: return "系统日历访问已关闭，可在系统设置中重新允许"
        case .restricted: return "系统限制了日历访问，可使用下方的订阅链接"
        case .notDetermined: return "尚未请求系统日历权限"
        @unknown default: return "日历权限状态未知，可使用下方的订阅链接"
        }
    }

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo")) {
        isDemo = demo
        snapshot = demo ? SampleData.make() : ScheduleSnapshot()
        if !demo {
            do {
                let storage = try SharedRepository.application()
                repository = storage
                if let loaded = try storage.load() { snapshot = loaded }
            } catch { errorMessage = "读取本地数据失败：\(error.localizedDescription)。原文件会在下次保存前备份。" }
        }
        calendarObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.snapshot.importedCalendar == nil else { return }
                    await self.refreshCalendar()
                }
            }
    }

    func reloadWidgets() {
        guard !isDemo else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "CampusScheduleWidget")
    }

    func connectIfAuthorized() async {
        guard !isDemo else { return }
        if snapshot.importedCalendar != nil { await refreshCalendar(); return }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        if calendarStatus == .fullAccess { await refreshCalendar() }
    }

    func showDemo() {
        guard !isDemo else { return }
        isDemo = true
        snapshot = SampleData.make()
        errorMessage = nil
    }

    func leaveDemo() async {
        do {
            let storage = try SharedRepository.application()
            let original = try storage.load() ?? ScheduleSnapshot()
            repository = storage
            snapshot = original
            isDemo = false
            await connectIfAuthorized()
        } catch { errorMessage = "无法打开本地数据：\(error.localizedDescription)" }
    }

    func requestCalendarAccess() async {
        guard !isDemo, !isRequestingCalendarAccess else { return }
        isRequestingCalendarAccess = true
        defer { isRequestingCalendarAccess = false }
        calendarMessage = nil
        do {
            let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
                ? true : try await calendarReader.requestAccess()
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
            if granted { await reloadCalendarList() }
            else { calendarMessage = "未获得日历读取权限。请在系统设置 → 隐私与安全性 → 日历中允许访问，或直接连接课表订阅。" }
        } catch {
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
            calendarMessage = "无法读取日历：\(error.localizedDescription)"
        }
    }

    func reloadCalendarList() async {
        guard !isDemo else { return }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        guard calendarStatus == .fullAccess else { calendars = []; return }
        // EventKit may retain an empty cache if the store existed before permission changed.
        calendars = await calendarReader.calendars(reset: true)
        guard !isDemo else { return }
        calendarMessage = calendars.isEmpty
            ? "系统已授权，但 EventKit 没有返回日历。请确认系统日历里能看到课表，或直接使用订阅链接。"
            : "已读取 \(calendars.count) 个系统日历，勾选学校课表后点击“保存设置”。"
        if snapshot.importedCalendar == nil && !snapshot.settings.calendarIDs.isEmpty { await refreshCalendar() }
    }

    func refreshCalendar() async {
        guard !isDemo, !isRefreshing else { return }
        if let imported = snapshot.importedCalendar {
            if let url = imported.subscriptionURL { await connectSubscription(url) }
            else { applyImportedCalendar(imported) }
            return
        }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        guard calendarStatus == .fullAccess else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard !snapshot.settings.calendarIDs.isEmpty else { return }
        let requestedSettings = snapshot.settings
        let result = await calendarReader.read(calendarIDs: requestedSettings.calendarIDs, interval: requestedSettings.interval())
        guard !isDemo, snapshot.settings == requestedSettings, snapshot.importedCalendar == nil else { return }
        calendars = result.calendars
        guard let events = result.events else {
            calendarMessage = "部分课表日历已不可用。请重新选择；当前保留上次同步的课表。"
            return
        }
        snapshot.registerCourses(events)
        snapshot.occurrences = events
        snapshot.syncedAt = Date()
        persist()
        calendarMessage = "同步完成：当前学期 \(Set(events.map(\.courseKey)).count) 门课程，\(events.count) 次上课。"
        if events.isEmpty { calendarMessage = "日历已读取，但当前学期内没有课程。请检查所选日历与学期起止日期。" }
    }

    func applySettings(_ settings: ScheduleSettings) async {
        let selectionChanged = settings.calendarIDs != snapshot.settings.calendarIDs
        snapshot.settings = settings
        if selectionChanged {
            snapshot.occurrences = []; snapshot.syncedAt = nil
            if let imported = snapshot.importedCalendar, settings.calendarIDs != [imported.sourceID] { snapshot.importedCalendar = nil }
        }
        persist()
        await refreshCalendar()
    }

    func connectSubscription(_ text: String) async {
        guard !isDemo, !isRefreshing else { return }
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("webcal://") { raw = "https://" + raw.dropFirst(9) }
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil else {
            calendarMessage = "请输入完整的 https:// 或 webcal:// 日历订阅链接。"; return
        }
        isRefreshing = true
        calendarMessage = "正在读取学校订阅…"
        defer { isRefreshing = false }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let source = ICalendarParser.sourceID(for: url)
            // Parsing dates is independent of EventKit and preserves the school's explicit timezone.
            let parsed = try await Task.detached(priority: .userInitiated) {
                try ICalendarParser.parse(data, sourceID: source)
            }.value
            guard !isDemo else { return }
            applyImportedCalendar(.init(name: parsed.name, sourceID: source, subscriptionURL: url.absoluteString, events: parsed.events))
        } catch {
            calendarMessage = "读取失败：\(error.localizedDescription)。已保留原课表。"
        }
    }

    func importCalendarFile(_ url: URL) {
        guard !isDemo, !isRefreshing else { return }
        do {
            let source = "ics-file:" + url.lastPathComponent
            let parsed = try ICalendarParser.parse(Data(contentsOf: url), sourceID: source)
            applyImportedCalendar(.init(name: parsed.name, sourceID: source, events: parsed.events))
        } catch { calendarMessage = "导入失败：\(error.localizedDescription)。已保留原课表。" }
    }

    private func applyImportedCalendar(_ imported: ImportedCalendar) {
        snapshot.importedCalendar = imported
        snapshot.settings.calendarIDs = [imported.sourceID]
        let interval = snapshot.settings.interval()
        let events = imported.events.filter { $0.start < interval.end && $0.end > interval.start }
        snapshot.registerCourses(events)
        snapshot.occurrences = events
        snapshot.syncedAt = Date()
        persist()
        calendarMessage = "读取成功：订阅共 \(imported.events.count) 次上课，当前学期 \(Set(events.map(\.courseKey)).count) 门课程、\(events.count) 次上课。"
        if events.isEmpty { calendarMessage! += "请在“学期与提醒”中调整日期范围。" }
    }

    func saveProfile(_ profile: CourseProfile) {
        guard let index = snapshot.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        snapshot.profiles[index] = profile
        persist()
    }

    func saveTodo(_ todo: TodoItem) {
        var clean = todo
        clean.title = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.title.isEmpty else { return }
        if let index = snapshot.todos.firstIndex(where: { $0.id == todo.id }) { snapshot.todos[index] = clean }
        else { snapshot.todos.append(clean) }
        persist()
    }

    func toggleTodo(_ id: UUID) {
        guard let index = snapshot.todos.firstIndex(where: { $0.id == id }) else { return }
        snapshot.todos[index].isCompleted.toggle()
        persist()
    }

    func deleteTodo(_ id: UUID) { snapshot.todos.removeAll { $0.id == id }; persist() }

    func saveHomework(_ homework: HomeworkAssignment) throws {
        try snapshot.upsertHomework(homework)
        if !persist() { throw CocoaError(.fileWriteUnknown) }
    }

    func toggleHomework(_ id: UUID) { snapshot.toggleHomework(id); persist() }

    func toggleHomeworkSubtask(_ id: UUID, in homeworkID: UUID) {
        snapshot.toggleHomeworkSubtask(id, in: homeworkID)
        persist()
    }

    func deleteHomework(_ id: UUID) { snapshot.removeHomework(id); persist() }

    func examDraft(for event: CourseOccurrence) -> ExamRecord {
        if let id = event.examID, let exam = snapshot.examRecords.first(where: { $0.id == id }) { return exam }
        if let exam = snapshot.examRecords.first(where: { $0.replaces(event) }) { return exam }
        return .marking(event)
    }

    func saveExam(_ exam: ExamRecord) {
        guard snapshot.upsertExam(exam) else { errorMessage = "考试名称不能为空，结束时间必须晚于开始时间。"; return }
        persist()
    }

    func deleteExam(_ id: UUID) { snapshot.removeExam(id); persist() }

    func restoreBackup(_ url: URL) {
        guard !isDemo else { errorMessage = "请先退出演示模式，再恢复数据。"; return }
        guard !snapshot.hasUserData else {
            errorMessage = "当前已经有课表或个人数据，未覆盖任何内容。请先确认是否需要合并备份。"
            return
        }
        do {
            let restored = try SharedRepository.decodeBackup(Data(contentsOf: url))
            snapshot = restored
            if persist() { calendarMessage = "课表、老师、待办、作业、考试数据已恢复。" }
        } catch { errorMessage = "备份读取失败：\(error.localizedDescription)" }
    }

    @discardableResult
    private func persist() -> Bool {
        guard !isDemo else { return true }
        do {
            guard let repository else { throw CocoaError(.fileWriteUnknown) }
            do { try repository.save(snapshot) }
            catch {
                guard repository.isShared else { throw error }
                let local = try SharedRepository.localApplication()
                try local.save(snapshot)
                self.repository = local
            }
            if self.repository?.isShared == true { WidgetCenter.shared.reloadTimelines(ofKind: "CampusScheduleWidget") }
            return true
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)。请保持应用打开并重试。"
            return false
        }
    }
}
