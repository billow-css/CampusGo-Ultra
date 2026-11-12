import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject private var manager: ModuleManager
    @Environment(\.nuistAccent) private var ink
    let onOpen: (String, Bool) -> Void
    let onSummary: () -> Void
    @State private var query = ""
    @State private var filter = "all"
    var body: some View {
        let modules = manager.registry.descriptors.filter {
            (query.isEmpty || ($0.name + $0.description).localizedCaseInsensitiveContains(query)) &&
            (filter == "all" || (filter == "enabled" ? manager.isEnabled($0.id) : manager.isPinned($0.id)))
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("发现").font(.system(size: 29, weight: .semibold))
                        Text("按需启用功能，把常用卡片放进摘要。").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("整理摘要", action: onSummary).buttonStyle(.bordered)
                }
                HStack(spacing: 18) {
                    Picker("功能筛选", selection: $filter) {
                        Text("全部功能").tag("all")
                        Text("已启用").tag("enabled")
                        Text("已加入摘要").tag("summary")
                    }.pickerStyle(.segmented).frame(maxWidth: 390)
                    Spacer()
                    TextField("搜索功能", text: $query).textFieldStyle(.roundedBorder).frame(width: 210)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 550), spacing: 18)], spacing: 18) {
                    ForEach(modules) { descriptor in moduleCard(descriptor) }
                }
                if modules.isEmpty {
                    Text("这里还没有匹配的功能。").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(40)
                }
            }.padding(28)
        }
    }
    private func moduleCard(_ descriptor: ModuleDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                Image(systemName: descriptor.icon).font(.system(size: 25, weight: .medium)).foregroundStyle(ink)
                    .frame(width: 50, height: 50).background(ink.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(descriptor.name).font(.system(size: 19, weight: .semibold))
                    Text(manager.isEnabled(descriptor.id) ? "已启用 · 内置功能" : "已关闭 · 内置功能")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("启用" + descriptor.name, isOn: Binding(get: { manager.isEnabled(descriptor.id) }, set: { manager.setEnabled(descriptor.id, $0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            Text(descriptor.description).font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            HStack(spacing: 8) {
                if descriptor.surfaces.contains(.summary) { tag("摘要卡片") }
                if descriptor.surfaces.contains(.detail) { tag("独立页面") }
                if descriptor.surfaces.contains(.overlay) { tag("窗口悬浮") }
            }
            Divider()
            HStack(spacing: 10) {
                if descriptor.surfaces.contains(.summary) {
                    Button {
                        if manager.isPinned(descriptor.id) { manager.unpin(descriptor.id) } else { manager.pin(descriptor.id) }
                    } label: {
                        Label(manager.isPinned(descriptor.id) ? "已加入摘要" : "加入摘要", systemImage: manager.isPinned(descriptor.id) ? "checkmark" : "plus")
                    }.buttonStyle(.bordered)
                        .help(manager.isPinned(descriptor.id) ? "从摘要移除卡片，功能保持当前启用状态" : "启用功能并添加摘要卡片")
                }
                Spacer(minLength: 0)
                if descriptor.surfaces.contains(.settings) {
                    Button("设置") { onOpen(descriptor.id, true) }.buttonStyle(.borderless)
                }
                Button(descriptor.surfaces.contains(.detail) ? "打开" : "查看") {
                    onOpen(descriptor.id, !descriptor.surfaces.contains(.detail))
                }.buttonStyle(.borderedProminent).disabled(!manager.isEnabled(descriptor.id))
            }.controlSize(.small)
        }.padding(22).background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(CampusTheme.boardLine) }
    }
    private func tag(_ title: String) -> some View {
        Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5).background(Color.primary.opacity(0.035), in: Capsule())
    }
}

struct SummaryModulesView: View {
    @EnvironmentObject private var manager: ModuleManager
    @EnvironmentObject private var store: AppStore
    let onOpen: (String, Bool) -> Void
    let onDiscover: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的模块").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onDiscover) { Label("添加功能", systemImage: "plus") }.buttonStyle(.borderless).font(.system(size: 11))
            }
            if manager.summaryModules.isEmpty {
                Button(action: onDiscover) {
                    Label("去发现，添加喜欢的功能", systemImage: "square.grid.2x2")
                        .font(.system(size: 13)).frame(maxWidth: .infinity).padding(28)
                        .background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(manager.summaryModules) { descriptor in
                        VStack(spacing: 5) {
                            HStack {
                                Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.secondary)
                                    .padding(4).draggable(descriptor.id).help("拖动这里调整卡片顺序")
                                Spacer()
                                Menu {
                                    Button("向前移动") { manager.shift(descriptor.id, by: -1) }
                                    Button("向后移动") { manager.shift(descriptor.id, by: 1) }
                                    if descriptor.surfaces.contains(.settings) { Button("设置") { onOpen(descriptor.id, true) } }
                                    Button("移出摘要") { manager.unpin(descriptor.id) }
                                } label: { Image(systemName: "ellipsis") }
                                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }
                            let context = manager.context(for: descriptor.id, store: store, returnTitle: "返回摘要", open: onOpen, close: {})
                            if let content = manager.module(descriptor.id)?.summaryCard(context: context) { content }
                        }.dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first, manager.registry.descriptor(id) != nil else { return false }
                            return manager.move(id, to: descriptor.id)
                        }
                    }
                }
            }
        }
    }
}

struct ModulePage: View {
    @EnvironmentObject private var manager: ModuleManager
    @EnvironmentObject private var store: AppStore
    let id: String
    let showingSettings: Bool
    let returnTitle: String
    let onOpen: (String, Bool) -> Void
    let onBack: () -> Void
    var body: some View {
        if let module = manager.module(id) {
            let context = manager.context(for: id, store: store, returnTitle: returnTitle, open: onOpen, close: onBack)
            if showingSettings || !module.descriptor.surfaces.contains(.detail) {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: onBack) { Label(returnTitle, systemImage: "chevron.left") }.buttonStyle(.plain)
                        Spacer()
                        Text(module.descriptor.name + "设置").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Toggle("启用", isOn: Binding(get: { manager.isEnabled(id) }, set: { manager.setEnabled(id, $0) })).toggleStyle(.switch).controlSize(.small)
                    }.padding(22)
                    Divider()
                    if let content = module.settings(context: context) { content }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if manager.isEnabled(id) {
                if let content = module.detail(context: context) { content }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: module.descriptor.icon).font(.largeTitle)
                    Text(module.descriptor.name + "已关闭").font(.title2)
                    Button("启用功能") { manager.setEnabled(id, true) }.buttonStyle(.borderedProminent)
                    Button(returnTitle, action: onBack)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ModuleOverlayHost: View {
    @EnvironmentObject private var manager: ModuleManager
    @EnvironmentObject private var store: AppStore
    let onOpen: (String, Bool) -> Void
    var body: some View {
        ZStack {
            ForEach(manager.overlayModules) { descriptor in
                let context = manager.context(for: descriptor.id, store: store, returnTitle: "返回发现", open: onOpen, close: {})
                if let content = manager.module(descriptor.id)?.overlay(context: context) { content }
            }
        }
    }
}

struct PetModuleCard: View {
    @EnvironmentObject private var pet: WindowPetStore
    @Environment(\.nuistAccent) private var ink
    let onSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("窗口桌宠", systemImage: "pawprint").font(.system(size: 13, weight: .semibold)); Spacer(); Text("陪伴中").font(.system(size: 10)).foregroundStyle(.secondary) }
            HStack(spacing: 15) {
                Image(nsImage: pet.artwork).resizable().scaledToFit().frame(width: 90, height: 100)
                Text("点击弹一下，长按蓄力。把它放在喜欢的位置，写几句自己的台词。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 9)
            Spacer(minLength: 0)
            Button(action: onSettings) { Label("调整大小与台词", systemImage: "slider.horizontal.3") }
                .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(ink)
        }.padding(18).frame(maxWidth: .infinity).frame(height: 252)
            .background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(CampusTheme.boardLine) }
    }
}
