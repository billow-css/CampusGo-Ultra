import SwiftUI

@main
struct CampusScheduleApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var appearance = AppearanceStore()
    @StateObject private var modules = ModuleHostState()
    var body: some Scene {
        WindowGroup("CampusGo Ultra") {
            ContentView().environmentObject(store)
                .environmentObject(appearance).environmentObject(modules.timer).environmentObject(modules.pet).environmentObject(modules.manager)
                .environment(\.nuistAccent, appearance.accent.color)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 1080, minHeight: 730)
        }
        .defaultSize(width: 1240, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("同步课表") { Task { await store.refreshCalendar() } }.keyboardShortcut("r")
                Button("查看示例课表") { store.showDemo() }
                Button("恢复 CampusGo Ultra 数据备份…") { store.requestingBackupImport = true }
            }
        }
        Settings {
            SettingsView().environmentObject(store).environmentObject(appearance).environmentObject(modules.timer).environmentObject(modules.pet).environmentObject(modules.manager)
                .environment(\.nuistAccent, appearance.accent.color)
                .preferredColorScheme(appearance.colorScheme).frame(width: 840, height: 640)
        }
    }
}
