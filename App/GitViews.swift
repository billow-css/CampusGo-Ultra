import SwiftUI
import Combine

private enum GitTheme { static let accent = Color.orange }
struct GitModule: CampusModule {
    let git: GitStore
    let descriptor = ModuleDescriptor(id: "campus.git", name: "Git", description: "关注项目进展：提交分支图、活跃度、GitHub PR、Issue 与 CI 状态。", icon: ModuleIcon.gitBranch, surfaces: [.summary, .detail, .settings, .navigation])
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
    @State private var previewNode: GitGraphNode?
    @State private var remoteTarget: GitHubDetailTarget?
    @State private var showGitHubAccess = false
    @State private var section = "graph"
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 205)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let error = git.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if let warnings = git.hub?.warnings, !warnings.isEmpty {
                        ForEach(warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
                        }
                    }
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
                        ContentUnavailableView {
                            Label { Text("关注你的项目") } icon: { ModuleIcon(name: ModuleIcon.gitBranch, size: 34) }
                        } description: {
                            Text("添加 GitHub 仓库，或关联本地项目。")
                        }
                    }
                }.padding(26)
            }
        }.background(Color(nsColor: .windowBackgroundColor)).tint(GitTheme.accent)
            .onAppear { git.refreshIfDue() }
            .onReceive(ticker) { _ in if NSApp.isActive && previewNode == nil && remoteTarget == nil { git.refreshIfDue() } }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in if previewNode == nil && remoteTarget == nil { git.refreshIfDue() } }
            .onChange(of: git.selectedID) { _, _ in section = "graph" }
            .sheet(isPresented: $addSheet) { addProject }
            .sheet(item: $previewNode, onDismiss: git.closeCommitDetail) { node in
                GitCommitDetailView(node: node) { previewNode = nil }
            }
            .sheet(item: $remoteTarget) { target in
                GitRemoteDetailView(target: target) { remoteTarget = nil }
            }
            .sheet(isPresented: $showGitHubAccess) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("GitHub 访问设置").font(.title2.bold())
                    GitHubAccessFields()
                    HStack { Spacer(); Button("完成") { showGitHubAccess = false } }.disabled(git.changingGitHubToken)
                }.padding(24).frame(width: 490)
            }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label { Text("项目关注") } icon: { ModuleIcon(name: ModuleIcon.gitBranch, size: 18) }.font(.system(size: 16, weight: .semibold)).padding(.top, 9)
            Button { addSheet = true } label: { Label("添加项目", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(git.busy)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(git.repositories) { repo in
                        Button { git.select(repo.id) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Label(repo.name, systemImage: repo.github == nil ? "folder" : "network").font(.system(size: 12, weight: .medium)).lineLimit(2)
                                Text(repo.github == nil ? "本地项目" : "GitHub").font(.system(size: 10)).foregroundStyle(.secondary)
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
            if git.selected?.github != nil {
                Button { showGitHubAccess = true } label: { Image(systemName: "key") }
                    .help("设置 GitHub 访问令牌")
            }
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
                    previewNode = row.node
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
                Text("最近 CI 运行").font(.headline)
                ForEach(hub.runs) { run in
                    Button { remoteTarget = .run(run) } label: {
                        HStack {
                            Image(systemName: run.failed ? "xmark.circle.fill" : run.conclusion == "success" ? "checkmark.circle.fill" : "clock")
                                .foregroundStyle(run.failed ? Color.red : .green)
                            Text(run.name ?? "Workflow")
                            Spacer()
                            Text(run.conclusion ?? run.status).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(git.busy)
                }
                if hub.runs.isEmpty { Text("暂无可用运行记录").foregroundStyle(.secondary) }
                Divider(); Text("最近开放 PR").font(.headline)
                ForEach(hub.pulls) { item in itemRow(item, target: .pull(item)) }
                if hub.pulls.isEmpty { Text("暂无可用 PR").foregroundStyle(.secondary) }
                Divider(); Text("最近开放 Issue").font(.headline)
                ForEach(hub.issues) { item in itemRow(item, target: .issue(item)) }
                if hub.issues.isEmpty { Text("暂无可用 Issue").foregroundStyle(.secondary) }
            } else { Text("刷新后显示 GitHub 项目动态").foregroundStyle(.secondary) }
        }.font(.system(size: 12)).padding(22).frame(maxWidth: .infinity, alignment: .leading).gitPanel()
    }
    private func itemRow(_ item: GitHubItem, target: GitHubDetailTarget) -> some View {
        Button { remoteTarget = target } label: {
            HStack {
                Text("#\(item.number)").foregroundStyle(GitTheme.accent)
                Text(item.title).lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(git.busy)
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
            Text("粘贴 GitHub 仓库链接，即可关注项目动态。").foregroundStyle(.secondary)
            TextField("https://github.com/owner/repo", text: $repositoryURL).textFieldStyle(.roundedBorder)
            HStack { Button("选择本地项目…") { addSheet = false; git.addRepository() }; Spacer(); Button("取消") { addSheet = false }; Button("关注") { git.addGitHub(repositoryURL); addSheet = false }.buttonStyle(.borderedProminent).disabled(GitHubActivityService.identifier(repositoryURL) == nil) }
        }.padding(25).frame(width: 500)
    }
}

private struct GitCommitDetailView: View {
    @EnvironmentObject private var git: GitStore
    let node: GitGraphNode
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label { Text("提交详情") } icon: { ModuleIcon(name: ModuleIcon.gitBranch, size: 14) }
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Spacer()
                    Button("关闭", action: close).keyboardShortcut(.cancelAction)
                }
                Text(node.subject).font(.title2.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                HStack(spacing: 12) {
                    Text(String(node.id.prefix(12))).font(.system(.caption, design: .monospaced))
                        .padding(5).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    Text(node.author)
                    Text(node.date.formatted(date: .abbreviated, time: .shortened))
                }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(20).background(CampusTheme.board)
            Divider()
            if git.previewLoading {
                ProgressView("正在读取提交…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = git.commitDetailError {
                ContentUnavailableView {
                    Label("无法读取提交", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { git.openCommit(node) }
                }
            } else if let detail = git.commitDetail {
                detailBody(detail)
            }
        }.frame(width: 860, height: 580)
    }

    private func detailBody(_ detail: GitCommitDetail) -> some View {
        let messageBody = detail.message.split(separator: "\n", maxSplits: 1).dropFirst().first
        return VStack(spacing: 0) {
            if let messageBody, !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView { Text(messageBody).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14) }
                    .frame(maxHeight: 105)
                Divider()
            }
            GitChangedFilesView(files: detail.files, note: detail.note)
        }
    }
}

private struct GitChangedFilesView: View {
    let files: [GitCommitDetail.File]
    var note: String?
    @State private var selectedFile = 0

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text("改动文件 · \(files.count)").font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary).padding(8)
                    if let note = note { Text(note).font(.caption).foregroundStyle(.secondary).padding(8) }
                    ForEach(files.indices, id: \.self) { index in
                        let file = files[index]
                        Button { selectedFile = index } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(file.filename).font(.caption).lineLimit(2).truncationMode(.middle)
                                if let added = file.additions, let removed = file.deletions {
                                    HStack(spacing: 8) {
                                        Text("+\(added)").foregroundStyle(.green)
                                        Text("−\(removed)").foregroundStyle(.red)
                                    }.font(.system(.caption2, design: .monospaced))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(selectedFile == index ? Color.orange.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).help(file.filename)
                    }
                }.padding(10)
            }.frame(width: 240)
            Divider()
            if files.indices.contains(selectedFile) {
                diffView(files[selectedFile]).id(selectedFile)
            } else {
                ContentUnavailableView("无文件变更", systemImage: "doc.text")
            }
        }
    }

    private func diffView(_ file: GitCommitDetail.File) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(file.filename).font(.caption.weight(.medium)).textSelection(.enabled)
                .padding(12)
            Divider()
            if let patch = file.patch, !patch.isEmpty {
                let lines = patch.prefix(200_000).split(separator: "\n", omittingEmptySubsequences: false)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines.indices, id: \.self) { index in
                            let line = lines[index]
                            let color: Color = line.hasPrefix("+") ? .green : line.hasPrefix("-") ? .red : line.hasPrefix("@@") ? .blue : .clear
                            Text(line.isEmpty ? " " : String(line))
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 2)
                                .background(color.opacity(0.12))
                        }
                        if patch.count > 200_000 { Text("此文件的差异预览已截断").padding(10).foregroundStyle(.secondary) }
                    }
                }
            } else {
                ContentUnavailableView("无文本差异", systemImage: "doc.text",
                                       description: Text("二进制文件或没有可显示的补丁。"))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct GitRemoteDetailView: View {
    @EnvironmentObject private var git: GitStore
    @State private var detail: GitHubRemoteDetail?
    @State private var error: String?
    @State private var retry = 0
    @State private var pane = "conversation"
    let target: GitHubDetailTarget
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label { Text(target.label) } icon: { ModuleIcon(name: ModuleIcon.gitBranch, size: 14) }
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Spacer()
                    Button("关闭", action: close).keyboardShortcut(.cancelAction)
                }
                Text(target.title).font(.title2.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                if let repository = git.selected?.github {
                    Text(repository).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(CampusTheme.board)
            Divider()
            if let detail {
                switch detail {
                case .discussion(let discussion, let comments, let files, let warnings):
                    discussionBody(discussion, comments: comments, files: files, warnings: warnings)
                case .run(let run, let jobs, let total):
                    runBody(run, jobs: jobs, total: total)
                }
            } else if let error {
                ContentUnavailableView {
                    Label("无法读取详情", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { retry += 1 }
                }
            } else {
                ProgressView("正在读取详情…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(width: 860, height: 580)
            .task(id: retry) {
                error = nil
                do { detail = try await git.remoteDetail(target) }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
    }

    private func discussionBody(_ discussion: GitHubDiscussion, comments: [GitHubComment]?,
                                files: [GitCommitDetail.File]?, warnings: [String]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                let isMerged = discussion.merged == true
                let isOpen = discussion.state == "open"
                let status = isMerged ? "已合并" : !isOpen ? "已关闭" : discussion.draft == true ? "草稿" : "开放"
                badge(status, color: isMerged ? .purple : isOpen ? .green : .secondary)
                if let source = discussion.head?.ref, let destination = discussion.base?.ref {
                    Text(source + " → " + destination).font(.system(.caption, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if let files {
                    Picker("显示", selection: $pane) {
                        Text("讨论").tag("conversation")
                        Text("文件 · \(files.count)").tag("files")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
            }.padding(12)
            Divider()
            if pane == "files", let files {
                GitChangedFilesView(files: files, note: files.count == 100 ? "仅预览前 100 个改动文件。" : nil)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        post(author: discussion.user?.login, date: discussion.created_at,
                             body: discussion.body ?? "未填写说明。")
                        if let comments {
                            Text("评论 · \(discussion.comments ?? comments.count)").font(.headline)
                            if (discussion.comments ?? comments.count) > comments.count {
                                Text("显示前 \(comments.count) 条评论。").font(.caption).foregroundStyle(.secondary)
                            }
                            if comments.isEmpty { Text("暂无评论").font(.caption).foregroundStyle(.secondary) }
                            ForEach(comments) { post(author: $0.user?.login, date: $0.created_at, body: $0.body) }
                        }
                    }.padding(16)
                }
            }
        }
    }

    private func post(author: String?, date: String?, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(author ?? "未知作者", systemImage: "person.crop.circle").font(.callout.weight(.semibold))
                Spacer()
                dateLabel(date)
            }
            let excerpt = String(body.prefix(30_000))
            Text((try? AttributedString(markdown: excerpt, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                 ?? AttributedString(excerpt))
                .font(.callout).textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { _ in .discarded })
            if body.count > 30_000 { Text("内容已截断").font(.caption).foregroundStyle(.secondary) }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).gitPanel()
    }

    private func runBody(_ run: GitHubRun, jobs: [GitHubJob], total: Int) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    runStatus(run.status, run.conclusion)
                    if let branch = run.head_branch { Label(branch, systemImage: "arrow.triangle.branch") }
                    if let event = run.event { Text(event) }
                    if let attempt = run.run_attempt { Text("第 \(attempt) 次运行") }
                    Spacer()
                    dateLabel(run.created_at)
                }.font(.caption).padding(14).gitPanel()
                Text("任务 · \(total)").font(.headline)
                if jobs.isEmpty { Text("暂无任务").foregroundStyle(.secondary) }
                if total > jobs.count {
                    Text("显示前 \(jobs.count) 个任务。").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(jobs) { job in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(job.name).font(.callout.weight(.semibold)); Spacer(); runStatus(job.status, job.conclusion) }
                        ForEach(job.steps ?? []) { step in
                            Divider()
                            HStack {
                                Text("\(step.number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 20)
                                Text(step.name).font(.callout)
                                Spacer()
                                runStatus(step.status, step.conclusion)
                            }
                        }
                    }.padding(14).gitPanel()
                }
            }.padding(16)
        }
    }

    @ViewBuilder private func dateLabel(_ date: String?) -> some View {
        if let date, let value = try? Date(date, strategy: .iso8601) {
            Text(value.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func runStatus(_ status: String, _ conclusion: String?) -> some View {
        let value = conclusion ?? status
        switch value {
        case "success": return badge("成功", color: .green)
        case "failure": return badge("失败", color: .red)
        case "timed_out": return badge("超时", color: .red)
        case "action_required": return badge("等待处理", color: .orange)
        case "cancelled": return badge("已取消", color: .secondary)
        case "skipped": return badge("已跳过", color: .secondary)
        case "queued", "waiting", "pending", "requested": return badge("等待中", color: .secondary)
        case "in_progress": return badge("运行中", color: .orange)
        case "completed": return badge("已完成", color: .secondary)
        default: return badge(value, color: .secondary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.12), in: Capsule())
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
                HStack { Label { Text(git.selected?.name ?? "项目关注") } icon: { ModuleIcon(name: ModuleIcon.gitBranch, size: 16) }.lineLimit(1); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 14, weight: .semibold))
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
                Text("支持 GitHub 仓库和授权的本地项目。添加项目请进入 Git 页面。")
                Text("当前项目在页面打开或应用回到前台时按需刷新，前台页面每 15 分钟更新。关闭插件会停止请求。")
                Text("本地提交图来自已有 Git 引用，不自动 fetch；远程同步请在编辑器完成。公开仓库可以匿名访问，私有仓库需要有读取权限的令牌。")
                Text("公开接口可能限流；失败时保留上次内容和更新时间。")
            }.font(.system(size: 12))
            Section("GitHub 访问") { GitHubAccessFields() }
        }.formStyle(.grouped)
    }
}

private struct GitHubAccessFields: View {
    @EnvironmentObject private var git: GitStore
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("公开仓库可以匿名访问。添加访问令牌可提高请求额度，也可查看令牌授权的私有仓库。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            SecureField("GitHub 访问令牌", text: $token).textFieldStyle(.roundedBorder)
                .disabled(git.changingGitHubToken)
            HStack {
                Link("创建令牌 ↗", destination: URL(string: "https://github.com/settings/personal-access-tokens")!)
                Spacer()
                Button("移除令牌") { apply(nil) }
                Button("保存并刷新") { apply(token) }.buttonStyle(.borderedProminent)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.disabled(git.changingGitHubToken)
            if let message = git.githubTokenStatus {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("建议使用细粒度令牌，并按需为仓库授予 Contents、Pull requests、Issues 和 Actions 的读取权限。令牌保存在 macOS 钥匙串。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private func apply(_ value: String?) {
        Task {
            if await git.setGitHubToken(value) {
                token = ""
                if git.selected?.github != nil { git.refresh() }
            }
        }
    }
}
