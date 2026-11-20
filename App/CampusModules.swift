import SwiftUI
import Combine

/// Versioned in-process module API. Modules receive values and explicit actions, not AppStore.
@MainActor
struct ModuleDataAccess {
    private let permissions: Set<ModulePermission>
    private let snapshot: () -> ScheduleSnapshot
    private let create: (TodoItem) -> Void
    private let homeworkWriter: (HomeworkAssignment) throws -> Void
    init(permissions: Set<ModulePermission>, snapshot: @escaping () -> ScheduleSnapshot,
         createTodo: @escaping (TodoItem) -> Void, saveHomework: @escaping (HomeworkAssignment) throws -> Void) {
        self.permissions = permissions; self.snapshot = snapshot; create = createTodo; homeworkWriter = saveHomework
    }
    private func require(_ permission: ModulePermission) throws {
        guard permissions.contains(permission) else { throw ModuleError.missingPermission }
    }
    func courses() throws -> [CourseOccurrence] { try require(.readCourses); return snapshot().schedule }
    func courseProfiles() throws -> [CourseProfile] { try require(.readCourses); return snapshot().profiles }
    func homework() throws -> [HomeworkAssignment] { try require(.readHomework); return snapshot().homeworkRecords }
    func todos() throws -> [TodoItem] { try require(.readTodos); return snapshot().todos }
    func createTodo(_ item: TodoItem) throws { try require(.createTodo); create(item) }
    func saveHomework(_ assignment: HomeworkAssignment) throws { try require(.writeHomework); try homeworkWriter(assignment) }
}

@MainActor
struct ModuleContext {
    let storage: ModuleStorage
    let data: ModuleDataAccess
    let openDetail: () -> Void
    let openSettings: () -> Void
    let close: () -> Void
    let returnTitle: String
    var navigationVisible: Binding<Bool>? = nil
}

@MainActor
protocol CampusModule {
    var descriptor: ModuleDescriptor { get }
    var defaultEnabled: Bool { get }
    var defaultPinned: Bool { get }
    var defaultNavigationVisible: Bool { get }
    var navigationTitle: String? { get }
    var enabledPublisher: AnyPublisher<Bool, Never>? { get }
    var changesPublisher: AnyPublisher<Void, Never>? { get }
    func setEnabled(_ enabled: Bool)
    func summaryCard(context: ModuleContext) -> AnyView?
    func detail(context: ModuleContext) -> AnyView?
    func settings(context: ModuleContext) -> AnyView?
    func overlay(context: ModuleContext) -> AnyView?
    func calendarIndicator(on day: Date, calendar: Calendar) -> ModuleDayIndicator?
}
extension CampusModule {
    var defaultEnabled: Bool { true }
    var defaultPinned: Bool { false }
    var defaultNavigationVisible: Bool { true }
    var navigationTitle: String? { nil }
    var enabledPublisher: AnyPublisher<Bool, Never>? { nil }
    var changesPublisher: AnyPublisher<Void, Never>? { nil }
    func calendarIndicator(on day: Date, calendar: Calendar) -> ModuleDayIndicator? { nil }
    func setEnabled(_ enabled: Bool) {}
    func summaryCard(context: ModuleContext) -> AnyView? { nil }
    func detail(context: ModuleContext) -> AnyView? { nil }
    func settings(context: ModuleContext) -> AnyView? { nil }
    func overlay(context: ModuleContext) -> AnyView? { nil }
}

@MainActor
final class ModuleManager: ObservableObject {
    let registry: ModuleRegistry
    @Published private(set) var layout: ModuleLayout
    @Published private(set) var navigation: NavigationPreferences
    private let modules: [String: any CampusModule]
    private let defaults: UserDefaults
    private let layoutKey = "campus.modules.layout.v1"
    private let navigationKey = "campus.navigation.v1"
    private var subscriptions: [AnyCancellable] = []
    init(modules: [any CampusModule], defaults: UserDefaults = .standard) throws {
        registry = try ModuleRegistry(modules.map(\.descriptor))
        self.modules = Dictionary(uniqueKeysWithValues: modules.map { ($0.descriptor.id, $0) })
        self.defaults = defaults
        var initialNavigation = defaults.data(forKey: navigationKey).flatMap { try? JSONDecoder().decode(NavigationPreferences.self, from: $0) } ?? NavigationPreferences()
        let introducedKey = "campus.navigation.introduced.v1"
        var introduced = Set(defaults.stringArray(forKey: introducedKey) ?? [])
        for module in modules where module.descriptor.surfaces.contains(.navigation) {
            if introduced.insert(module.descriptor.id).inserted && !module.defaultNavigationVisible {
                initialNavigation.setVisible("nav." + module.descriptor.id, false)
            }
        }
        defaults.set(Array(introduced).sorted(), forKey: introducedKey)
        navigation = initialNavigation
        if let data = try? JSONEncoder().encode(initialNavigation) { defaults.set(data, forKey: navigationKey) }
        let saved = defaults.data(forKey: layoutKey).flatMap { try? JSONDecoder().decode(ModuleLayout.self, from: $0) }
        var layout = saved ?? ModuleLayout()
        layout.normalize(registry: registry, defaults: Dictionary(uniqueKeysWithValues: modules.map { ($0.descriptor.id, $0.defaultEnabled) }),
                         initialPins: modules.filter { $0.defaultPinned && (saved == nil || saved?.enabled[$0.descriptor.id] == nil) }.map { $0.descriptor.id })
        self.layout = layout
        for module in modules { module.setEnabled(layout.enabled[module.descriptor.id] == true) }
        for module in modules {
            if let publisher = module.changesPublisher {
                subscriptions.append(publisher.sink { [weak self] in self?.objectWillChange.send() })
            }
            if let publisher = module.enabledPublisher {
                let id = module.descriptor.id
                subscriptions.append(publisher.sink { [weak self] enabled in self?.synchronize(id, enabled: enabled) })
            }
        }
        save()
    }
    private func save() { if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: layoutKey) } }
    private func synchronize(_ id: String, enabled: Bool) {
        guard registry.descriptor(id) != nil, layout.enabled[id] != enabled else { return }
        layout.enabled[id] = enabled; save()
    }
    func module(_ id: String) -> (any CampusModule)? { modules[id] }
    func navigationTitle(for id: String) -> String {
        let custom = modules[id]?.navigationTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? (registry.descriptor(id)?.name ?? "") : custom
    }
    func isEnabled(_ id: String) -> Bool { layout.enabled[id] == true }
    func isPinned(_ id: String) -> Bool { layout.summaryOrder.contains(id) }
    var summaryModules: [ModuleDescriptor] { layout.visibleSummaryIDs.compactMap { registry.descriptor($0) } }
    var overlayModules: [ModuleDescriptor] { registry.descriptors.filter { isEnabled($0.id) && $0.surfaces.contains(.overlay) } }
    var availableNavigationModules: [ModuleDescriptor] { registry.descriptors.filter { $0.surfaces.contains(.navigation) } }
    var navigationModules: [ModuleDescriptor] { availableNavigationModules.filter { isTabVisible("nav." + $0.id) } }
    func temporaryNavigationModule(_ id: String?) -> ModuleDescriptor? {
        guard let id, isEnabled(id), let descriptor = registry.descriptor(id), descriptor.surfaces.contains(.detail),
              !navigationModules.contains(where: { $0.id == id }) else { return nil }
        return descriptor
    }
    func isTabVisible(_ id: String) -> Bool {
        guard navigation.isVisible(id) else { return false }
        if id.hasPrefix("nav.") { return isEnabled(String(id.dropFirst(4))) }
        return true
    }
    func setTabVisible(_ id: String, _ visible: Bool) {
        guard !NavigationPreferences.fixedTabs.contains(id) else { return }
        if visible, id.hasPrefix("nav.") { setEnabled(String(id.dropFirst(4)), true) }
        navigation.setVisible(id, visible)
        if let data = try? JSONEncoder().encode(navigation) { defaults.set(data, forKey: navigationKey) }
    }
    func calendarIndicators(on day: Date, calendar: Calendar) -> [ModuleDayIndicator] {
        registry.descriptors.filter { isEnabled($0.id) && $0.surfaces.contains(.calendarIndicator) }
            .compactMap { modules[$0.id]?.calendarIndicator(on: day, calendar: calendar) }
    }
    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let module = modules[id], layout.enabled[id] != enabled else { return }
        layout.enabled[id] = enabled
        module.setEnabled(enabled); save()
    }
    func pin(_ id: String) {
        guard registry.descriptor(id)?.surfaces.contains(.summary) == true else { return }
        setEnabled(id, true)
        layout.pin(id, registry: registry); save()
    }
    func unpin(_ id: String) { layout.unpin(id); save() }
    @discardableResult func move(_ id: String, to target: String) -> Bool {
        let changed = layout.move(id, to: target)
        if changed { save() }
        return changed
    }
    func shift(_ id: String, by offset: Int) {
        let ids = layout.visibleSummaryIDs
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        move(id, to: ids[index + offset])
    }
    func context(for id: String, store: AppStore, returnTitle: String,
                 open: @escaping (String, Bool) -> Void, close: @escaping () -> Void) -> ModuleContext {
        let permissions = registry.descriptor(id)?.permissions ?? []
        // Registry IDs are validated at registration, so the scoped storage key is valid.
        let storage = try! ModuleStorage(moduleID: id, defaults: defaults)
        return ModuleContext(storage: storage,
            data: ModuleDataAccess(permissions: permissions, snapshot: { store.snapshot },
                createTodo: { store.saveTodo($0) }, saveHomework: { try store.saveHomework($0) }),
            openDetail: { open(id, false) }, openSettings: { open(id, true) }, close: close, returnTitle: returnTitle,
            navigationVisible: registry.descriptor(id)?.surfaces.contains(.navigation) == true ? Binding(
                get: { self.isTabVisible("nav." + id) }, set: { self.setTabVisible("nav." + id, $0) }) : nil)
    }
}

@MainActor
struct PomodoroModule: CampusModule {
    let timer: PomodoroStore
    let descriptor = ModuleDescriptor(id: "campus.pomodoro", name: "番茄钟", description: "25 分钟专注、5 分钟休息，支持循环、独立标签页与全窗口专注空间。", icon: "timer", surfaces: [.summary, .detail, .settings, .navigation])
    var defaultPinned: Bool { true }
    var defaultNavigationVisible: Bool { false }
    func setEnabled(_ enabled: Bool) { timer.setModuleEnabled(enabled) }
    func summaryCard(context: ModuleContext) -> AnyView? { AnyView(PomodoroCard(onExpand: context.openDetail, onSettings: context.openSettings).environmentObject(timer)) }
    func detail(context: ModuleContext) -> AnyView? { AnyView(FocusPage(onBack: context.close, backTitle: context.returnTitle, navigationVisible: context.navigationVisible).environmentObject(timer)) }
    func settings(context: ModuleContext) -> AnyView? { AnyView(PomodoroSettingsView(navigationVisible: context.navigationVisible).environmentObject(timer)) }
}

@MainActor
struct PetModule: CampusModule {
    let pet: WindowPetStore
    let descriptor = ModuleDescriptor(id: "campus.window-pet", name: "窗口桌宠", description: "放在窗口里的小伙伴，支持拖动、果冻弹跳和自定义台词。", icon: "pawprint", surfaces: [.summary, .settings, .overlay])
    var defaultEnabled: Bool { pet.enabled }
    var defaultPinned: Bool { true }
    var enabledPublisher: AnyPublisher<Bool, Never>? { pet.$enabled.eraseToAnyPublisher() }
    func setEnabled(_ enabled: Bool) { if pet.enabled != enabled { pet.enabled = enabled } }
    func summaryCard(context: ModuleContext) -> AnyView? { AnyView(PetModuleCard(onSettings: context.openSettings).environmentObject(pet)) }
    func settings(context: ModuleContext) -> AnyView? { AnyView(WindowPetSettingsView().environmentObject(pet)) }
    func overlay(context: ModuleContext) -> AnyView? { AnyView(WindowPetOverlay().environmentObject(pet)) }
}

@MainActor
final class ModuleHostState: ObservableObject {
    let timer: PomodoroStore
    let pet: WindowPetStore
    let sci: GoSciStore
    let git: GitStore
    let manager: ModuleManager
    init(defaults: UserDefaults = .standard) {
        let timer = PomodoroStore(defaults: defaults)
        let pet = WindowPetStore(defaults: defaults)
        let sci = GoSciStore(defaults: defaults)
        let git = GitStore(defaults: defaults)
        self.timer = timer; self.pet = pet; self.sci = sci; self.git = git
        // Built-ins use the same versioned registration path as future internal modules.
        manager = try! ModuleManager(modules: [PomodoroModule(timer: timer), PetModule(pet: pet), GoSciModule(planner: sci), GitModule(git: git)], defaults: defaults)
    }
}
