import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.nuistAccent) private var themeAccent
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var page = "schedule"
    @State private var activeModule = "campus.pomodoro"
    @State private var moduleSettings = false
    @State private var moduleOrigin = "discover"
    @State private var weekOffset = 0
    @State private var showingSettings = false
    private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()
    private func openModule(_ id: String, settings: Bool, origin: String) {
        activeModule = id; moduleSettings = settings; moduleOrigin = origin; page = "module"
    }
    var body: some View {
        VStack(spacing: 0) {
            AppNavigationBar(page: $page, moduleOrigin: moduleOrigin) { showingSettings = true }
            if store.snapshot.settings.calendarIDs.isEmpty && !store.isDemo {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.plus")
                    Text("连接已订阅的学校日历，自动生成课表。")
                    Spacer()
                    Button("先看示例") { store.showDemo() }
                    Button("选择课表日历") { showingSettings = true }.buttonStyle(.borderedProminent).tint(themeAccent)
                }.padding(14).background(themeAccent.opacity(0.08))
            }
            if page == "module" {
                ModulePage(id: activeModule, showingSettings: moduleSettings,
                    returnTitle: moduleOrigin == "home" ? "返回摘要" : "返回发现",
                    onOpen: { id, settings in openModule(id, settings: settings, origin: moduleOrigin) },
                    onBack: { page = moduleOrigin })
            } else if page == "work" {
                WorkOverviewPage()
            } else if page == "discover" {
                DiscoveryView(onOpen: { id, settings in openModule(id, settings: settings, origin: "discover") }, onSummary: { page = "home" })
            } else {
            HSplitView {
                Group {
                    if page == "home" {
                        HomeView(onOpenSchedule: { page = "schedule"; weekOffset = 0 },
                            onOpenModule: { id, settings in openModule(id, settings: settings, origin: "home") }, onDiscover: { page = "discover" })
                    } else {
                        VStack(spacing: 0) {
                            WeekCalendarView(weekOffset: $weekOffset)
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                ReminderBoard(snapshot: store.snapshot, now: timeline.date)
                                    .padding(.horizontal, 24).padding(.vertical, 15)
                                    .background(CampusTheme.board)
                            }
                        }
                    }
                }.frame(minWidth: 740, maxWidth: .infinity, maxHeight: .infinity)
                VSplitView {
                    TodoListView().frame(minHeight: 200, idealHeight: 280, maxHeight: .infinity)
                    HomeworkListView().frame(minHeight: 230, idealHeight: 350, maxHeight: .infinity)
                }.frame(minWidth: 285, idealWidth: 310, maxWidth: 350, maxHeight: .infinity)
            }
            }
        }.background(Color(nsColor: .windowBackgroundColor)).tint(themeAccent)
            .overlay { ModuleOverlayHost { id, settings in openModule(id, settings: settings, origin: "discover") } }
            .sheet(isPresented: $showingSettings) {
                SettingsView().environmentObject(store).frame(width: 840, height: 640)
            }
            .fileImporter(isPresented: $store.requestingBackupImport, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    store.restoreBackup(url)
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError { store.errorMessage = error.localizedDescription }
                }
            }
            .alert("CampusGo Ultra", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("好", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
            .task { store.reloadWidgets(); await store.connectIfAuthorized() }
            .onOpenURL { url in if url.host == "today" { page = "schedule"; weekOffset = 0 } }
            .onReceive(refreshTimer) { _ in Task { await store.connectIfAuthorized() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.connectIfAuthorized() } }
            }
    }
}
