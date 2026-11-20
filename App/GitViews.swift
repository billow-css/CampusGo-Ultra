import SwiftUI
import Combine

private enum GitTheme { static let accent = Color.orange }
struct GitModule: CampusModule {
    let git: GitStore
    let descriptor = ModuleDescriptor(id: "campus.git", name: "Git", description: "关注项目进展：提交分支图、活跃度、GitHub PR、Issue 与 CI 状态。", icon: "point.3.connected.trianglepath.dotted", surfaces: [.summary, .detail, .settings, .navigation])
    var defaultNavigationVisible: Bool { false }
    var changesPublisher: AnyPublisher<Void, Never>? { git.objectWillChange.eraseToAnyPublisher() }
    func setEnabled(_ enabled: Bool) { git.setEnabled(enabled) }
    func summaryCard(context: ModuleContext) -> AnyView? { AnyView(GitSummaryCard(onOpen: context.openDetail).environmentObject(git)) }
    func detail(context: ModuleContext) -> AnyView? { AnyView(GitPage().environmentObject(git)) }
    func settings(context: ModuleContext) -> AnyView? { AnyView(GitSettings(navigationVisible: context.navigationVisible).environmentObject(git)) }
}
struct GitPage: View {
    @EnvironmentObject private var git: GitStore
    @State private var addSheet = false
    @State private var repositoryURL = ""
    @State private var showPreview = false
    @State private var section = "graph"
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let error = git.errorMessage { Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                    if git.selected != nil {
                        hero
                        if git.selected?.github == nil { GitActivityGrid(dates: git.snapshot.activityDates) }
                        Picker("项目内容", selection: $section) {
                            Text("提交图").tag("graph")
                            if git.selected?.github != nil { Text("PR / Issue / CI").tag("activity") }
                            else { Text("工作区概览").tag("workspace") }
                        }.pickerStyle(.segmented).frame(width: 340)
                        if section == "graph" { graph }
                        else if git.selected?.github != nil { remoteActivity }
                        else { workspace }
                    } else {
                        ContentUnavailableView("关注你的项目", systemImage: "point.3.connected.trianglepath.dotted", description: Text("添加公开 GitHub 仓库，或关联本地项目。"))
                    }
                }.padding(26)
            }
        }.background(Color(nsColor: .windowBackgroundColor)).tint(GitTheme.accent)
            .onAppear { git.refreshIfDue() }
            .onReceive(ticker) { _ in if NSApp.isActive { git.refreshIfDue() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in git.refreshIfDue() }
            .onChange(of: git.selectedID) { _, _ in section = "graph" }
            .sheet(isPresented: $addSheet) { addProject }
            .sheet(isPresented: $showPreview) { preview }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("项目关注", systemImage: "point.3.connected.trianglepath.dotted").font(.system(size: 16, weight: .semibold)).padding(.top, 9)
            Button { addSheet = true } label: { Label("添加项目", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(git.busy)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(git.repositories) { repo in
                        Button { git.select(repo.id) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Label(repo.name, systemImage: repo.github == nil ? "folder" : "network").font(.system(size: 12, weight: .medium)).lineLimit(2)
                                Text(repo.github == nil ? "本地项目" : "GitHub · 公开仓库").font(.system(size: 10)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                                .background(git.selectedID == repo.id ? GitTheme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(git.busy)
                    }
                }
            }
            Text("打开页面时按需更新，前台每 15 分钟刷新当前项目。").font(.system(size: 10)).foregroundStyle(.secondary)
            Button("移除关注", action: git.removeSelected).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary).disabled(git.selected == nil || git.busy)
        }.padding(16)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(git.selected?.name ?? "Git").font(.system(size: 25, weight: .semibold))
                HStack {
                    if let date = git.refreshedAt { Text("上次更新 " + date.formatted(date: .abbreviated, time: .shortened)) }
                    else { Text("尚未更新") }
                    if git.selected?.github == nil { Text("· 本地记录，远程状态以最近一次外部同步为准") }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if git.busy { ProgressView().controlSize(.small); Button("取消", action: git.cancel) }
            else { Button(action: git.refresh) { Image(systemName: "arrow.clockwise") }.disabled(git.selected == nil) }
            Button(git.selected?.github == nil ? "打开文件夹" : "打开仓库", action: git.openProject).disabled(git.selected == nil)
        }.buttonStyle(.bordered).controlSize(.small)
    }
    private var hero: some View {
        let failed = git.hub?.runs.filter(\.failed).count ?? 0
        let latest = git.nodes.first
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(failed > 0 ? "需要关注 · CI 运行失败" : "项目动态", systemImage: failed > 0 ? "exclamationmark.circle.fill" : "waveform.path")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(failed > 0 ? Color.red : GitTheme.accent)
                Spacer()
                if git.selected?.github == nil { Label(git.snapshot.branch, systemImage: "arrow.triangle.branch").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            Text(latest?.subject ?? (git.busy ? "正在读取项目…" : "暂无提交记录")).font(.system(size: 25, weight: .semibold)).lineLimit(2)
            if let latest { Text(latest.author + " · " + latest.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12)).foregroundStyle(.secondary) }
            if let hub = git.hub {
                if !hub.description.isEmpty { Text(hub.description).font(.system(size: 12)).foregroundStyle(.secondary) }
                HStack(spacing: 24) { stat("近期开放 PR", hub.pulls.count); stat("近期开放 Issue", hub.issues.count); stat("最近运行失败", failed) }
                Text("列表为最近更新的部分记录，计数不代表仓库总量，也不表示分配给你。").font(.system(size: 10)).foregroundStyle(.tertiary)
            } else if git.selected?.github == nil {
                HStack(spacing: 24) { stat("本地分支", git.snapshot.branches.count); stat("变更文件", git.snapshot.files.count); Text(git.snapshot.tracking).font(.system(size: 12)).foregroundStyle(.secondary) }
            }
        }.padding(24).gitPanel()
    }
    private func stat(_ title: String, _ count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) { Text("\(count)").font(.system(size: 22, weight: .semibold, design: .rounded)); Text(title).font(.system(size: 11)).foregroundStyle(.secondary) }
    }
    private var graph: some View {
        let rows = GitGraphLayout.rows(git.nodes)
        return VStack(alignment: .leading, spacing: 0) {
            HStack { Text("提交脉络").font(.system(size: 16, weight: .semibold)); Spacer(); Text(git.selected?.github == nil ? "全部本地引用 · 最近 80 条" : "默认分支 · 最近 80 条").font(.system(size: 11)).foregroundStyle(.secondary) }.padding(18)
            Divider()
            if rows.isEmpty { Text("暂无可显示的提交图").foregroundStyle(.secondary).padding(25) }
            ForEach(rows) { row in
                Button {
                    git.openCommit(row.node)
                    if git.selected?.github == nil { showPreview = true }
                } label: {
                    HStack(spacing: 12) {
                        GitGraphRail(row: row).frame(width: 100, height: 60)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.node.subject).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            HStack(spacing: 9) {
                                Text(String(row.id.prefix(7))).fontDesign(.monospaced).foregroundStyle(GitTheme.accent)
                                Text(row.node.author).lineLimit(1)
                                Text(row.node.date, style: .date)
                                if !row.node.refs.isEmpty { Text(row.node.refs).foregroundStyle(.green).lineLimit(1) }
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.padding(.horizontal, 16).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(git.busy)
            }
            Text("连线表示真实父提交关系；跨出当前记录范围的连线在边缘结束。").font(.system(size: 10)).foregroundStyle(.tertiary).padding(16)
        }.gitPanel()
    }
    private var remoteActivity: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let hub = git.hub {
                ForEach(hub.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                Text("最近 CI 运行").font(.headline)
                ForEach(hub.runs) { run in
                    Link(destination: run.html_url) { HStack { Image(systemName: run.failed ? "xmark.circle.fill" : run.conclusion == "success" ? "checkmark.circle.fill" : "clock").foregroundStyle(run.failed ? Color.red : .green); Text(run.name ?? "Workflow"); Spacer(); Text(run.conclusion ?? run.status).foregroundStyle(.secondary) } }.buttonStyle(.plain)
                }
                if hub.runs.isEmpty { Text("暂无可用运行记录").foregroundStyle(.secondary) }
                Divider(); Text("最近开放 PR").font(.headline)
                ForEach(hub.pulls) { item in itemLink(item) }
                if hub.pulls.isEmpty { Text("暂无可用 PR").foregroundStyle(.secondary) }
                Divider(); Text("最近开放 Issue").font(.headline)
                ForEach(hub.issues) { item in itemLink(item) }
                if hub.issues.isEmpty { Text("暂无可用 Issue").foregroundStyle(.secondary) }
            } else { Text("刷新后显示 GitHub 项目动态").foregroundStyle(.secondary) }
        }.font(.system(size: 12)).padding(22).frame(maxWidth: .infinity, alignment: .leading).gitPanel()
    }
    private func itemLink(_ item: GitHubItem) -> some View {
        Link(destination: item.html_url) { HStack { Text("#\(item.number)").foregroundStyle(GitTheme.accent); Text(item.title).lineLimit(2); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.secondary) } }.buttonStyle(.plain)
    }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("工作区概览").font(.headline)
            Text("在熟悉的编辑器中继续工作，这里只提示当前项目状态。").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(git.snapshot.files) { file in HStack { Text(file.label).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.orange).frame(width: 35); Text(file.path).font(.system(size: 12)).textSelection(.enabled); Spacer() } }
            if git.snapshot.files.isEmpty { Label("工作区干净", systemImage: "checkmark.circle").foregroundStyle(.green) }
        }.padding(22).gitPanel()
    }
    private var addProject: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("关注项目").font(.title2.bold())
            Text("公开 GitHub 仓库，无需克隆即可查看动态。").foregroundStyle(.secondary)
            TextField("https://github.com/owner/repo", text: $repositoryURL).textFieldStyle(.roundedBorder)
            HStack { Button("选择本地项目…") { addSheet = false; git.addRepository() }; Spacer(); Button("取消") { addSheet = false }; Button("关注") { git.addGitHub(repositoryURL); addSheet = false }.buttonStyle(.borderedProminent).disabled(GitHubActivityService.identifier(repositoryURL) == nil) }
        }.padding(25).frame(width: 500)
    }
    private var preview: some View {
        VStack {
            HStack { Text("提交详情").font(.headline); Spacer(); Button("关闭") { showPreview = false } }.padding()
            if git.previewLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ScrollView([.horizontal, .vertical]) { Text(git.preview).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading) } }
        }.frame(width: 850, height: 560)
    }
}
private extension View {
    func gitPanel() -> some View { background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 13)).overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(CampusTheme.boardLine) } }
}
struct GitGraphLayout {
    struct Row: Identifiable {
        let node: GitGraphNode
        let lane: Int
        var totalLanes = 1
        let incoming: [(Int, Int)]
        let outgoing: [(Int, Int)]
        var id: String { node.id }
    }
    static func rows(_ nodes: [GitGraphNode]) -> [Row] {
        var lanes: [String] = []; var rows: [Row] = []
        for node in nodes {
            let existingLanes = lanes
            if !lanes.contains(node.id) { lanes.append(node.id) }
            let before = lanes; let lane = lanes.firstIndex(of: node.id)!
            lanes.remove(at: lane)
            for parent in node.parents.reversed() where !lanes.contains(parent) { lanes.insert(parent, at: min(lane, lanes.count)) }
            let incoming = existingLanes.enumerated().map { ($0.offset, $0.offset) }
            var outgoing: [(Int, Int)] = []
            for (index, hash) in before.enumerated() where hash != node.id {
                if let target = lanes.firstIndex(of: hash) { outgoing.append((index, target)) }
            }
            for parent in node.parents { if let target = lanes.firstIndex(of: parent) { outgoing.append((lane, target)) } }
            rows.append(Row(node: node, lane: lane, incoming: incoming, outgoing: outgoing))
        }
        let width = 1 + (rows.flatMap { $0.incoming + $0.outgoing }.flatMap { [$0.0, $0.1] }.max() ?? 0)
        return rows.map { var row = $0; row.totalLanes = width; return row }
    }
}
private struct GitGraphRail: View {
    let row: GitGraphLayout.Row
    var body: some View {
        Canvas { context, size in
            let maximum = row.totalLanes - 1
            let spacing = min(15.0, (size.width - 14) / Double(max(1, maximum)))
            func x(_ lane: Int) -> CGFloat { 7 + Double(lane) * spacing }
            let colors: [Color] = [.orange, .green, .blue, .purple, .pink, .teal]
            for edge in row.incoming {
                var path = Path(); path.move(to: CGPoint(x: x(edge.0), y: 0)); path.addLine(to: CGPoint(x: x(edge.1), y: 30))
                context.stroke(path, with: .color(colors[edge.0 % colors.count].opacity(0.65)), lineWidth: 2)
            }
            for edge in row.outgoing {
                var path = Path(); path.move(to: CGPoint(x: x(edge.0), y: 30)); path.addCurve(to: CGPoint(x: x(edge.1), y: 60), control1: CGPoint(x: x(edge.0), y: 48), control2: CGPoint(x: x(edge.1), y: 42))
                context.stroke(path, with: .color(colors[edge.1 % colors.count].opacity(0.65)), lineWidth: 2)
            }
            context.fill(Path(ellipseIn: CGRect(x: x(row.lane) - 4, y: 26, width: 8, height: 8)), with: .color(colors[row.lane % colors.count]))
        }.accessibilityLabel("提交节点，\(row.node.parents.count) 个父提交")
    }
}
private struct GitActivityGrid: View {
    let dates: [Date]
    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let counts = Dictionary(grouping: dates, by: { calendar.startOfDay(for: $0) }).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 13) {
            HStack { Text("项目活跃度").font(.system(size: 14, weight: .semibold)); Spacer(); Text("近 84 天 · 全部本地引用").font(.system(size: 11)).foregroundStyle(.secondary) }
            HStack(spacing: 5) {
                ForEach(0..<12) { week in
                    VStack(spacing: 5) {
                        ForEach(0..<7) { day in
                            let date = calendar.date(byAdding: .day, value: week * 7 + day - 83, to: today)!
                            let count = counts[date] ?? 0
                            RoundedRectangle(cornerRadius: 3).fill(count == 0 ? Color.primary.opacity(0.055) : Color.green.opacity(min(1, 0.23 + Double(count) * 0.12)))
                                .frame(width: 16, height: 16).help(date.formatted(date: .abbreviated, time: .omitted) + " · \(count) 次提交")
                        }
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 6) { Text("\(dates.count)").font(.system(size: 28, weight: .semibold, design: .rounded)); Text("此时间范围内的提交").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }.padding(20).gitPanel()
    }
}
private struct GitSummaryCard: View {
    @EnvironmentObject private var git: GitStore
    let onOpen: () -> Void
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Label(git.selected?.name ?? "项目关注", systemImage: "point.3.connected.trianglepath.dotted").lineLimit(1); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 14, weight: .semibold))
                Text(git.nodes.first?.subject ?? "添加项目，随时查看进展").font(.system(size: 19, weight: .semibold)).lineLimit(2)
                if let date = git.refreshedAt { Text("更新于 " + date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).gitPanel()
        }.buttonStyle(.plain).onAppear { git.refreshIfDue() }
    }
}
private struct GitSettings: View {
    @EnvironmentObject private var git: GitStore
    var navigationVisible: Binding<Bool>?
    var body: some View {
        Form {
            if let navigationVisible { Toggle("在顶部显示 Git 标签页", isOn: navigationVisible) }
            Section("项目动态看板") {
                Text("支持公开 GitHub 仓库和授权的本地项目。添加项目请进入 Git 页面。")
                Text("当前项目在页面打开或应用回到前台时按需刷新，前台页面每 15 分钟更新。关闭插件会停止请求。")
                Text("本地提交图来自已有 Git 引用，不自动 fetch；远程同步请在编辑器完成。GitHub 动态无需登录，当前不支持私有仓库、个人指派筛选及系统通知。")
                Text("公开接口可能限流；失败时保留上次内容和更新时间。")
            }.font(.system(size: 12))
        }.formStyle(.grouped)
    }
}
