import SwiftUI
import Combine

@MainActor
final class GoSciStore: ObservableObject {
    @Published private(set) var document = SciDocument()
    @Published var errorMessage: String?
    @Published private(set) var loadFailed = false
    @Published private(set) var deletedSession: SciSession?
    @Published private(set) var customNavigationTitle = ""
    @Published var poolInput = "" { didSet { changes.send() } }
    @Published private var slotInputs: [String: String] = [:]
    var navigationTitle: String {
        let trimmed = customNavigationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Agenda" : trimmed
    }
    private let storage: ModuleStorage
    private var pendingSave: AnyCancellable?
    private var termination: AnyCancellable?
    private let changes = PassthroughSubject<Void, Never>()
    init(defaults: UserDefaults = .standard) {
        storage = try! ModuleStorage(moduleID: "campus.gosci", defaults: defaults)
        customNavigationTitle = (try? storage.load(String.self, key: "navigation-title.v1")) ?? ""
        poolInput = (try? storage.load(String.self, key: "pool-input.v1")) ?? ""
        do {
            if let saved = try storage.load(SciDocument.self, key: "plan.v1") {
                try saved.validate()
                document = saved
                // Older versions left unused empty slots behind after switching selection.
                document.removeEmptySessions()
            }
        } catch { loadFailed = true; errorMessage = error.localizedDescription }
        pendingSave = changes.debounce(for: .milliseconds(250), scheduler: RunLoop.main).sink { [weak self] in self?.flush() }
        termination = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification).sink { [weak self] _ in self?.flush() }
    }
    @discardableResult func edit(_ action: (inout SciDocument) throws -> Void) -> Bool {
        guard !loadFailed else { return false }
        do {
            var next = document
            try action(&next)
            try next.validate()
            guard next != document else { return true }
            document = next
            changes.send()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func flush() {
        guard !loadFailed else { return }
        do {
            try storage.save(document, key: "plan.v1")
            try storage.save(poolInput, key: "pool-input.v1")
            for (key, text) in slotInputs { try storage.save(text, key: "slot-input." + key) }
        }
        catch { errorMessage = error.localizedDescription }
    }
    func select(day: Date, period: SciPeriod) -> String? {
        var id: String?
        if edit({ document in
            let existing = document.session(on: day, period: period)?.id
            document.removeEmptySessions(except: existing)
            id = document.ensureSession(on: day, period: period)
        }) { return id }
        return nil
    }
    func releaseSelection() { edit { $0.removeEmptySessions() }; flush() }
    func session(at slot: SciSlot) -> SciSession? { document.session(on: slot.day, period: slot.period) }
    func input(at slot: SciSlot) -> String {
        if let session = session(at: slot) { return session.draftText }
        return slotInputs[slot.id] ?? (try? storage.load(String.self, key: "slot-input." + slot.id)) ?? ""
    }
    func inputBinding(at slot: SciSlot) -> Binding<String> {
        Binding(get: { self.input(at: slot) }, set: { text in
            if let session = self.session(at: slot) { self.edit { try $0.setDraft(text, session: session.id) } }
            else { self.slotInputs[slot.id] = text; self.changes.send() }
        })
    }
    @discardableResult func addTasks(at slot: SciSlot) -> Bool {
        let text = input(at: slot)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let saved = edit { document in
            let id = document.ensureSession(on: slot.day, period: slot.period)
            try document.setDraft(text, session: id)
            try document.commitDraft(session: id)
        }
        if saved { slotInputs[slot.id] = ""; flush() }
        return saved
    }
    func addPoolInput() {
        guard !poolInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if edit({ $0.addToPool(poolInput) }) { poolInput = ""; flush() }
    }
    static let dragPrefix = "campusgo.agenda.task:"
    func moveTask(_ id: UUID, to slot: SciSlot?) -> Bool {
        let moved = edit { document in
            let pending = slot.map { input(at: $0) } ?? ""
            let destination = try document.moveTask(id, to: slot)
            if let destination, !pending.isEmpty { try document.setDraft(pending, session: destination) }
        }
        if moved {
            if let slot { slotInputs[slot.id] = "" }
            flush()
        }
        return moved
    }
    func acceptDrop(_ payloads: [String], to slot: SciSlot?) -> Bool {
        let ids = payloads.compactMap { value -> UUID? in
            guard value.hasPrefix(Self.dragPrefix) else { return nil }
            return UUID(uuidString: String(value.dropFirst(Self.dragPrefix.count)))
        }
        guard !ids.isEmpty else { return false }
        return ids.map { moveTask($0, to: slot) }.contains(true)
    }
    func toggle(_ task: SciTask, in session: SciSession) { edit { try $0.toggleTask(task.id, session: session.id) } }
    func draft(_ id: String) -> Binding<String> {
        Binding(get: { self.document.session(id)?.draftText ?? "" }, set: { text in self.edit { try $0.setDraft(text, session: id) } })
    }
    func commit(_ id: String) { edit { try $0.commitDraft(session: id) }; flush() }
    func postpone(_ id: String, now: Date = .now) -> String? {
        var target: String?
        if edit({ target = try $0.postpone(session: id, at: now) }) { flush(); return target }
        return nil
    }
    func toPool(_ id: String) { edit { try $0.moveToPool(session: id) }; flush() }
    func deleteSession(_ id: String) {
        var removed: SciSession?
        if edit({ removed = try $0.deleteSession(id) }) { deletedSession = removed; flush() }
    }
    @discardableResult func undoDelete() -> String? {
        guard let deletedSession else { return nil }
        var id: String?
        if edit({ id = $0.restoreSession(deletedSession) }) { self.deletedSession = nil; flush(); return id }
        return nil
    }
    func dismissUndo() { deletedSession = nil }
    func setNavigationTitle(_ title: String) {
        let title = String(title.components(separatedBy: .newlines).joined(separator: " ").prefix(120))
        guard title != customNavigationTitle else { return }
        do {
            try storage.save(title, key: "navigation-title.v1")
            customNavigationTitle = title
        } catch { errorMessage = error.localizedDescription }
    }
}

enum SciTheme {
    static let green = Color(nsColor: NSColor(name: "GoSciGrass") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.60, green: 0.82, blue: 0.32, alpha: 1)
            : NSColor(srgbRed: 0.32, green: 0.49, blue: 0.11, alpha: 1)
    })
    static let background = Color(nsColor: .windowBackgroundColor)
    static let board = CampusTheme.board
    static func dot(_ count: Int) -> Color {
        switch count {
        case 1: return Color(red: 0.64, green: 0.80, blue: 0.40)
        case 2: return Color(red: 0.37, green: 0.65, blue: 0.18)
        default: return green
        }
    }
    static func activityColor(_ count: Int) -> Color {
        guard count > 0 else { return Color.primary.opacity(0.035) }
        let level = min(3, (count - 1) / 2)
        return Color(nsColor: NSColor(name: "GoSciActivity\(level)") { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = (dark ? [0x283823, 0x3A542A, 0x527A32, 0x7EA942] : [0xE0EDC9, 0xB8D78B, 0x85B447, 0x527D20])[level]
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static func activityText(_ count: Int) -> Color {
        guard count >= 7 else { return CampusTheme.boardText }
        return Color(nsColor: NSColor(name: "GoSciActivityText") { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
        })
    }
}

extension ModuleAccent {
    var color: Color { switch self { case .grass: return SciTheme.green } }
    func indicatorColor(level: Int) -> Color { switch self { case .grass: return SciTheme.dot(level) } }
}

struct GoSciModule: CampusModule {
    let planner: GoSciStore
    let descriptor = ModuleDescriptor(id: "campus.gosci", name: "Agenda", description: "用上午、下午、夜间安排学习、工作与生活；勾选进度，灵活顺延，把暂未安排的任务收进池中。", icon: "leaf.fill",
        surfaces: [.summary, .detail, .settings, .navigation, .calendarIndicator], accent: .grass)
    var defaultPinned: Bool { true }
    var navigationTitle: String? { planner.navigationTitle }
    var changesPublisher: AnyPublisher<Void, Never>? { planner.objectWillChange.map { _ in () }.eraseToAnyPublisher() }
    func setEnabled(_ enabled: Bool) { if !enabled { planner.flush() } }
    func summaryCard(context: ModuleContext) -> AnyView? { AnyView(GoSciSummaryCard(onOpen: context.openDetail).environmentObject(planner)) }
    func detail(context: ModuleContext) -> AnyView? { AnyView(GoSciPage().environmentObject(planner)) }
    func settings(context: ModuleContext) -> AnyView? { AnyView(AgendaSettingsView().environmentObject(planner)) }
    func calendarIndicator(on day: Date, calendar: Calendar) -> ModuleDayIndicator? {
        let count = planner.document.plannedCount(on: day, calendar: calendar)
        return count == 0 ? nil : ModuleDayIndicator(count: count, label: "Agenda · \(count) 段安排", accent: .grass)
    }
}
