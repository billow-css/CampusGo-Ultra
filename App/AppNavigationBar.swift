import SwiftUI

struct AppNavigationBar: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var manager: ModuleManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionIndicator
    @State private var themeHovered = false
    @Binding var page: String
    var moduleOrigin = "discover"
    var expandedModuleID: String? = nil
    let onSettings: () -> Void
    var body: some View {
        let expanded = expandedModuleID.flatMap { manager.isEnabled($0) ? manager.registry.descriptor($0) : nil }
        let temporary = manager.temporaryNavigationModule(expandedModuleID)
        let selectedTab = temporary?.id ?? expanded.map { "nav." + $0.id } ?? (page == "module" ? moduleOrigin : page)
        return HStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 25, height: 25)
                Text("CampusGo Ultra").font(.system(size: 14, weight: .semibold))
            }.frame(width: 154, alignment: .leading)
            HStack(spacing: 14) {
                NavigationItem(title: "摘要", icon: "house", selected: selectedTab == "home", indicator: selectionIndicator) { page = "home" }
                NavigationItem(title: "课表", icon: "calendar", selected: selectedTab == "schedule", indicator: selectionIndicator) { page = "schedule" }
                if manager.isTabVisible("work") {
                    NavigationItem(title: "Plans", icon: "checklist", selected: selectedTab == "work", indicator: selectionIndicator) { page = "work" }
                }
                ForEach(manager.navigationModules) { descriptor in
                    NavigationItem(title: manager.navigationTitle(for: descriptor.id), icon: descriptor.icon,
                        selected: selectedTab == "nav." + descriptor.id, accent: descriptor.accent?.color, indicator: selectionIndicator) {
                        page = "nav." + descriptor.id
                    }
                }
                if let temporary {
                    HStack(spacing: 3) {
                        NavigationItem(title: manager.navigationTitle(for: temporary.id), icon: temporary.icon, selected: true, accent: temporary.accent?.color, indicator: selectionIndicator) {}
                        Button { page = moduleOrigin } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).padding(4) }
                            .buttonStyle(NavigationPressStyle()).foregroundStyle(.secondary).help("退出展开视图")
                    }
                }
                if manager.isTabVisible("discover") {
                    NavigationItem(title: "发现", icon: "square.grid.2x2", selected: selectedTab == "discover", indicator: selectionIndicator) { page = "discover" }
                }
            }.animation(reduceMotion ? nil : .smooth(duration: 0.24), value: selectedTab)
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
            HStack(spacing: 6) {
                Button { Task { await store.refreshCalendar() } } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 26) }
                    .disabled(store.isRefreshing || store.isDemo).help("同步课表")
                Menu {
                    Picker("界面模式", selection: $appearance.mode) {
                        ForEach(AppearanceStore.Mode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Divider()
                    Picker("强调色", selection: $appearance.accent) {
                        ForEach(AppearanceStore.Accent.allCases) { accent in Text(accent.title).tag(accent) }
                    }
                } label: {
                    Image(systemName: "paintpalette").frame(width: 24, height: 26)
                        .background(Color.primary.opacity(themeHovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("切换主题")
                .onHover { themeHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: themeHovered)
                Button(action: onSettings) { Image(systemName: "gearshape").frame(width: 24, height: 26) }.help("设置")
            }.font(.system(size: 14)).foregroundStyle(.secondary).buttonStyle(NavigationPressStyle())
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
    let indicator: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ModuleIcon(name: selected && icon == "house" ? "house.fill" : icon, size: 15)
                ScrollingTabTitle(title: title, selected: selected)
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? (accent ?? themeAccent) : Color.secondary)
            .padding(.horizontal, 6).frame(height: 55)
        }
        .buttonStyle(NavigationPressStyle())
        .overlay(alignment: .bottom) {
            if selected {
                Capsule().fill(accent ?? themeAccent)
                    .frame(width: 26, height: 2)
                    .matchedGeometryEffect(id: "selection", in: indicator)
                    .padding(.bottom, 1)
                    .allowsHitTesting(false)
            }
        }
        .help(title).accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct NavigationPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Feedback(configuration: configuration)
    }

    private struct Feedback: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration

        var body: some View {
            let pressed = enabled && configuration.isPressed
            let opacity = pressed ? 0.10 : enabled && hovered ? 0.05 : 0
            configuration.label
                .background(Color.primary.opacity(opacity), in: RoundedRectangle(cornerRadius: 7))
                .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
        }
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
