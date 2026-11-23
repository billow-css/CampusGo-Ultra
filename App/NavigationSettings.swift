import SwiftUI

struct NavigationSettingsView: View {
    @EnvironmentObject private var manager: ModuleManager
    @Environment(\.nuistAccent) private var accent
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("标签页").font(.title2).fontWeight(.semibold)
                    Text("选择顶栏中显示的页面，修改后立即生效并自动保存。")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    fixedRow("摘要", icon: "house")
                    Divider().padding(.leading, 48)
                    fixedRow("课表", icon: "calendar")
                }.background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(CampusTheme.boardLine) }
                VStack(spacing: 0) {
                    tabRow("Plans", icon: "checklist", id: "work", detail: "内置功能 · 个人日程与作业")
                    ForEach(manager.availableNavigationModules) { descriptor in
                        Divider().padding(.leading, 48)
                        tabRow(manager.navigationTitle(for: descriptor.id), icon: descriptor.icon, id: "nav." + descriptor.id,
                            detail: manager.isEnabled(descriptor.id) ? descriptor.name + " · 模块页面" : "开启标签页时同时启用模块", ink: descriptor.accent?.color)
                    }
                    Divider().padding(.leading, 48)
                    tabRow("发现", icon: "square.grid.2x2", id: "discover", detail: "浏览和管理功能模块")
                }.background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(CampusTheme.boardLine) }
                Label("隐藏标签页不会删除数据。摘要和课表固定显示；已启用模块的摘要卡片仍可使用。", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(24)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func fixedRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 22)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Label("固定显示", systemImage: "lock.fill").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(16)
    }
    private func tabRow(_ title: String, icon: String, id: String, detail: String, ink: Color? = nil) -> some View {
        HStack(spacing: 13) {
            ModuleIcon(name: icon, size: 16).foregroundStyle(ink ?? accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("显示" + title, isOn: Binding(get: { manager.isTabVisible(id) }, set: { manager.setTabVisible(id, $0) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(ink ?? accent)
        }.padding(16)
    }
}
