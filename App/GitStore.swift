import SwiftUI
import Combine

@MainActor
final class GitStore: ObservableObject {
    @Published private(set) var repositories: [GitRepository] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var snapshot = GitSnapshot()
    @Published private(set) var busy = false
    @Published private(set) var activity = ""
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var commitDetail: GitCommitDetail?
    @Published private(set) var commitDetailError: String?
    @Published private(set) var previewLoading = false
    @Published private(set) var selectedFile: String?
    @Published private(set) var selectedCommit: String?
    @Published var stagedPreview = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var hub: GitHubActivity?
    @Published var commitMessage = ""
    @Published var newBranch = ""
    @Published private(set) var changingGitHubToken = false
    @Published private(set) var githubTokenStatus: String?
    private let github = GitHubActivityService()
    private var remoteSnapshots: [UUID: (activity: GitHubActivity, date: Date)] = [:]
    private var lastRemoteAttempt: [UUID: Date] = [:]
    private let storage: ModuleStorage
    private var enabled = true
    private var loadFailed = false
    private var operation: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var generation = UUID()
    private var previewGeneration = UUID()
    var selected: GitRepository? { repositories.first { $0.id == selectedID } }
    var canCommit: Bool { !busy && snapshot.stagedCount > 0 && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !snapshot.files.contains(where: \.conflicted) }
    var currentFile: GitFileChange? { snapshot.files.first { $0.path == selectedFile } }

    init(defaults: UserDefaults = .standard) {
        storage = try! ModuleStorage(moduleID: "campus.git", defaults: defaults)
        do {
            repositories = try storage.load([GitRepository].self, key: "repositories.v1") ?? []
            selectedID = try storage.load(UUID.self, key: "selection.v1")
            if !repositories.contains(where: { $0.id == selectedID }) { selectedID = repositories.first?.id }
        } catch { loadFailed = true; errorMessage = "仓库列表无法读取，原数据已保留。" }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { cancel() }
    }
    func cancel() {
        generation = UUID(); operation?.cancel(); operation = nil
        previewGeneration = UUID(); previewTask?.cancel(); previewTask = nil
        busy = false; previewLoading = false
    }
    private func persist() {
        guard !loadFailed else { return }
        do {
            try storage.save(repositories, key: "repositories.v1")
            if let selectedID { try storage.save(selectedID, key: "selection.v1") }
            else { storage.remove(key: "selection.v1") }
        } catch { errorMessage = error.localizedDescription }
    }
    private func resolve(_ repo: GitRepository) throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: repo.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil),
               let index = repositories.firstIndex(where: { $0.id == repo.id }) {
                repositories[index].bookmark = data; persist()
            }
        }
        return url
    }
    func select(_ id: UUID) {
        guard !busy, selectedID != id else { return }
        cancel(); hub = nil; selectedID = id; snapshot = GitSnapshot(); refreshedAt = nil
        selectedFile = nil; selectedCommit = nil; commitDetail = nil; commitMessage = ""; notice = nil
        restoreRemoteSnapshot(); persist(); refreshIfDue()
    }
    func addRepository() {
        guard !busy, !loadFailed else { return }
        let panel = NSOpenPanel()
        panel.title = "添加 Git 仓库"; panel.message = "选择已有仓库的根文件夹。"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        start("正在接入仓库…") { [self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let result = try await GitService.run(["rev-parse", "--show-toplevel"], at: url).checked()
            let root = result.text.trimmingCharacters(in: .newlines)
            guard URL(fileURLWithPath: root).resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path else {
                throw GitFailure(message: "请选择仓库根文件夹：\(root)")
            }
            let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            let existing = repositories.first { (try? resolve($0).resolvingSymlinksInPath()) == url.resolvingSymlinksInPath() }
            let repo = existing ?? GitRepository(name: url.lastPathComponent, bookmark: data)
            let state = try await GitService.snapshot(at: url)
            try Task.checkCancellation()
            if existing == nil { repositories.append(repo) }
            selectedID = repo.id; hub = nil; snapshot = state; refreshedAt = .now
            selectedFile = nil; selectedCommit = nil; commitDetail = nil; commitMessage = ""
            persist(); notice = "已添加 \(repo.name)"
        }
    }
    func removeSelected() {
        guard !busy, let selectedID else { return }
        cancel(); repositories.removeAll { $0.id == selectedID }
        remoteSnapshots.removeValue(forKey: selectedID)
        lastRemoteAttempt.removeValue(forKey: selectedID)
        self.selectedID = repositories.first?.id; hub = nil; snapshot = GitSnapshot(); refreshedAt = nil
        selectedFile = nil; selectedCommit = nil; commitDetail = nil; commitMessage = ""
        restoreRemoteSnapshot(); persist(); notice = "已从列表移除，仓库文件保留。"; refreshIfDue()
    }
    private func start(_ title: String, body: @escaping @MainActor () async throws -> Void) {
        guard enabled, !busy else { return }
        previewTask?.cancel(); previewGeneration = UUID(); previewLoading = false
        let token = UUID(); generation = token
        busy = true; activity = title; errorMessage = nil; notice = nil
        operation = Task { [weak self] in
            do { try await body() }
            catch is CancellationError {}
            catch { if self?.generation == token { self?.errorMessage = String(error.localizedDescription.prefix(8000)) } }
            guard let self, generation == token else { return }
            busy = false; activity = ""; operation = nil

        }
    }
    func addGitHub(_ input: String) {
        guard let id = GitHubActivityService.identifier(input), !busy, !loadFailed else { errorMessage = "请输入 github.com 的仓库链接或 owner/repo。"; return }
        if let existing = repositories.first(where: { $0.github?.lowercased() == id.lowercased() }) { select(existing.id); return }
        let repo = GitRepository(name: id, bookmark: Data(), github: id)
        repositories.append(repo); selectedID = repo.id; snapshot = GitSnapshot(); hub = nil; refreshedAt = nil
        persist(); refresh()
    }
    private func restoreRemoteSnapshot() {
        guard let id = selectedID, let cached = remoteSnapshots[id] else { return }
        hub = cached.activity
        refreshedAt = cached.date
    }
    func setGitHubToken(_ value: String?) async -> Bool {
        guard !changingGitHubToken else { return false }
        let token = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token, token.isEmpty || !token.utf8.allSatisfy({ (33...126).contains($0) }) {
            githubTokenStatus = "请输入完整的 GitHub 访问令牌。"
            return false
        }
        changingGitHubToken = true
        defer { changingGitHubToken = false }
        if selected?.github != nil { cancel() }
        do {
            try await Task.detached {
                if let token { try GitHubTokenKeychain.save(token) }
                else { try GitHubTokenKeychain.remove() }
            }.value
            remoteSnapshots.removeAll()
            lastRemoteAttempt.removeAll()
            if selected?.github != nil { hub = nil; refreshedAt = nil; errorMessage = nil }
            githubTokenStatus = token == nil ? "已移除令牌，公开仓库将使用匿名请求。" : "令牌已存入钥匙串，刷新项目时将使用此令牌。"
        } catch {
            githubTokenStatus = error.localizedDescription
            return false
        }
        return true
    }
    func refreshIfDue() {
        guard let repo = selected else { return }
        let lastCheck = repo.github == nil ? refreshedAt : lastRemoteAttempt[repo.id]
        if lastCheck.map({ Date().timeIntervalSince($0) >= 900 }) ?? true { refresh() }
    }
    func refresh() {
        guard let repo = selected, !busy, enabled, !changingGitHubToken else { return }
        start("正在刷新…") { [self] in
            if let id = repo.github {
                lastRemoteAttempt[repo.id] = .now
                let token = try await Task.detached { try GitHubTokenKeychain.load() }.value
                try Task.checkCancellation()
                let result = try await github.load(id, token: token, previous: hub)
                try Task.checkCancellation()
                hub = result
                if result.warnings.isEmpty { refreshedAt = .now }
                if let refreshedAt {
                    if remoteSnapshots.count >= 16 && remoteSnapshots[repo.id] == nil { remoteSnapshots.removeAll() }
                    remoteSnapshots[repo.id] = (activity: result, date: refreshedAt)
                }
                return
            }
            let url = try resolve(repo); let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let result = try await GitService.snapshot(at: url)
            try Task.checkCancellation()
            snapshot = result; refreshedAt = .now
            if !result.files.contains(where: { $0.path == selectedFile }) { selectedFile = nil; commitDetail = nil }
            if let file = currentFile, stagedPreview && !file.staged { stagedPreview = false }
        }
    }
    var nodes: [GitGraphNode] { selected?.github == nil ? snapshot.nodes : (hub?.nodes ?? []) }
    func openProject() {
        if let id = selected?.github, let url = URL(string: "https://github.com/" + id) { NSWorkspace.shared.open(url) }
        else if let repo = selected, let url = try? resolve(repo) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func remoteDetail(_ target: GitHubDetailTarget) async throws -> GitHubRemoteDetail {
        guard let repo = selected?.github else { throw GitFailure(message: "请选择 GitHub 项目。") }
        let token = try await Task.detached { try GitHubTokenKeychain.load() }.value
        try Task.checkCancellation()
        return try await github.remoteDetail(repo: repo, target: target, token: token)
    }

    func closeCommitDetail() {
        previewTask?.cancel()
        previewTask = nil
        previewGeneration = UUID()
        previewLoading = false
        commitDetail = nil
        commitDetailError = nil
    }

    func openCommit(_ node: GitGraphNode) {
        guard !busy, let repo = selected else { return }
        closeCommitDetail()
        let generation = previewGeneration
        previewLoading = true
        previewTask = Task {
            do {
                let detail: GitCommitDetail
                if let id = repo.github {
                    let token = try await Task.detached { try GitHubTokenKeychain.load() }.value
                    try Task.checkCancellation()
                    detail = try await github.commitDetail(repo: id, sha: node.id, token: token)
                } else {
                    let url = try resolve(repo)
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let message = try await GitService.run(["show", "-s", "--format=%B", node.id, "--"], at: url).checked()
                    let patch = try await GitService.run(["show", "--format=", "--diff-merges=first-parent", "--patch", "--no-ext-diff", "--no-textconv", "--no-color", node.id, "--"], at: url).checked()
                    let files = patch.text.components(separatedBy: "\ndiff --git ").compactMap { section -> GitCommitDetail.File? in
                        guard !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                        let parts = section.split(separator: "\n", maxSplits: 1).map(String.init)
                        guard let heading = parts.first else { return nil }
                        let name = heading.hasPrefix("diff --git ") ? String(heading.dropFirst(11)) : heading
                        return .init(filename: name, patch: parts.count == 2 ? parts[1] : nil,
                                     status: nil, additions: nil, deletions: nil)
                    }
                    detail = .init(message: message.text, files: files)
                }
                guard previewGeneration == generation, !Task.isCancelled else { return }
                commitDetail = detail
            } catch {
                guard previewGeneration == generation, !Task.isCancelled else { return }
                commitDetailError = error.localizedDescription
            }
            if previewGeneration == generation { previewLoading = false }
        }
    }
}
