import SwiftUI

struct AppNavigationBar: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var manager: ModuleManager
    @Binding var page: String
    var moduleOrigin = "discover"
    var expandedModuleID: String? = nil
    let onSettings: () -> Void
    var body: some View {
        let expanded = expandedModuleID.flatMap { manager.isEnabled($0) ? manager.registry.descriptor($0) : nil }
        let temporary = manager.temporaryNavigationModule(expandedModuleID)
        return HStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 25, height: 25)
                Text("CampusGo Ultra").font(.system(size: 14, weight: .semibold))
            }.frame(width: 154, alignment: .leading)
            HStack(spacing: 14) {
                NavigationItem(title: "摘要", icon: "house", selected: page == "home" || (page == "module" && moduleOrigin == "home" && expanded == nil)) { page = "home" }
                NavigationItem(title: "课表", icon: "calendar", selected: page == "schedule") { page = "schedule" }
                if manager.isTabVisible("work") {
                    NavigationItem(title: "Plans", icon: "checklist", selected: page == "work") { page = "work" }
                }
                ForEach(manager.navigationModules) { descriptor in
                    NavigationItem(title: manager.navigationTitle(for: descriptor.id), icon: descriptor.icon,
                        selected: page == "nav." + descriptor.id || expanded?.id == descriptor.id || (page == "module" && moduleOrigin == "nav." + descriptor.id), accent: descriptor.accent?.color) {
                        page = "nav." + descriptor.id
                    }
                }
                if let temporary {
                    HStack(spacing: 3) {
                        NavigationItem(title: manager.navigationTitle(for: temporary.id), icon: temporary.icon, selected: true, accent: temporary.accent?.color) {}
                        Button { page = moduleOrigin } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).padding(4) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("退出展开视图")
                    }
                }
                if manager.isTabVisible("discover") {
                    NavigationItem(title: "发现", icon: "square.grid.2x2", selected: page == "discover" || (page == "module" && moduleOrigin == "discover" && expanded == nil)) { page = "discover" }
                }
            }
            if store.isDemo {
                Button("退出演示") { Task { await store.leaveDemo() } }
                    .font(.caption).padding(.leading, 20)
            }
            Spacer(minLength: 8)
            if store.isRefreshing { ProgressView().controlSize(.mini).padding(.trailing, 12) }
            if let date = store.snapshot.syncedAt {
                Text(date.formatted(.dateTime.hour().minute()) + " 已同步")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).frame(maxWidth: 64).padding(.trailing, 12)
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
        }.padding(.horizontal, 18).frame(height: 56).background(.bar)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5) }
    }
}

private struct NavigationItem: View {
    @Environment(\.nuistAccent) private var themeAccent
    let title: String
    let icon: String
    let selected: Bool
    var accent: Color? = nil
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected && icon == "house" ? "house.fill" : icon)
                ScrollingTabTitle(title: title, selected: selected)
            }
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? (accent ?? themeAccent) : Color.secondary)
                .padding(.horizontal, 6).frame(height: 55)
                .background(hovered ? Color.primary.opacity(0.035) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .bottom) {
                    if selected { Capsule().fill(accent ?? themeAccent).frame(width: 26, height: 2).padding(.bottom, 1) }
                }.contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.help(title).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ScrollingTabTitle: View {
    let title: String
    var selected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sliding = false
    private var textWidth: CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular)]).width)
    }
    private var visibleWidth: CGFloat { min(80, textWidth) }
    private var travel: CGFloat { max(0, textWidth - visibleWidth) }
    private var animationKey: String { title + "|\(selected)|\(reduceMotion)" }
    var body: some View {
        Group {
            if reduceMotion {
                Text(title).lineLimit(1).truncationMode(.tail).frame(width: visibleWidth, alignment: .leading)
            } else {
                Text(title).fixedSize(horizontal: true, vertical: false)
                    .offset(x: sliding ? -travel : 0)
                    .frame(width: visibleWidth, height: 18, alignment: .leading).clipped()
            }
        }.font(.system(size: 13, weight: selected ? .semibold : .regular))
            .task(id: animationKey) {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { sliding = false }
                guard !reduceMotion, travel > 0 else { return }
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                withAnimation(.linear(duration: max(2, Double(travel) / 24)).delay(1).repeatForever(autoreverses: true)) { sliding = true }
            }
    }
}
