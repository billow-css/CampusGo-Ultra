import SwiftUI

struct AppNavigationBar: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var appearance: AppearanceStore
    @Binding var page: String
    var moduleOrigin = "discover"
    let onSettings: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 25, height: 25)
                Text("CampusGo Ultra").font(.system(size: 14, weight: .semibold))
            }.frame(width: 154, alignment: .leading)
            HStack(spacing: 22) {
                NavigationItem(title: "摘要", icon: "house", selected: page == "home" || (page == "module" && moduleOrigin == "home")) { page = "home" }
                NavigationItem(title: "课表", icon: "calendar", selected: page == "schedule") { page = "schedule" }
                NavigationItem(title: "作业与日程", icon: "checklist", selected: page == "work") { page = "work" }
                NavigationItem(title: "发现", icon: "square.grid.2x2", selected: page == "discover" || (page == "module" && moduleOrigin == "discover")) { page = "discover" }
            }
            if store.isDemo {
                Button("退出演示") { Task { await store.leaveDemo() } }
                    .font(.caption).padding(.leading, 20)
            }
            Spacer(minLength: 16)
            if store.isRefreshing { ProgressView().controlSize(.mini).padding(.trailing, 12) }
            if let date = store.snapshot.syncedAt {
                Text(date.formatted(.dateTime.hour().minute()) + " 已同步")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.trailing, 15)
            }
            HStack(spacing: 14) {
                Button { Task { await store.refreshCalendar() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.isRefreshing || store.isDemo).help("同步课表")
                Menu {
                    Picker("界面模式", selection: $appearance.mode) {
                        ForEach(AppearanceStore.Mode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Divider()
                    Picker("强调色", selection: $appearance.accent) {
                        ForEach(AppearanceStore.Accent.allCases) { accent in Text(accent.title).tag(accent) }
                    }
                } label: { Image(systemName: "paintpalette") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("切换主题")
                Button(action: onSettings) { Image(systemName: "gearshape") }.help("设置")
            }.font(.system(size: 14)).foregroundStyle(.secondary).buttonStyle(.plain)
        }.padding(.horizontal, 22).frame(height: 56).background(.bar)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5) }
    }
}

private struct NavigationItem: View {
    @Environment(\.nuistAccent) private var themeAccent
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: selected && icon == "house" ? "house.fill" : icon)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? themeAccent : Color.secondary)
                .padding(.horizontal, 6).frame(height: 55)
                .background(hovered ? Color.primary.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .bottom) {
                    if selected { Capsule().fill(themeAccent).frame(width: 26, height: 2).padding(.bottom, 1) }
                }.contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
