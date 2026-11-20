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
    @Published private(set) var preview = ""
    @Published private(set) var previewLoading = false
    @Published private(set) var selectedFile: String?
    @Published private(set) var selectedCommit: String?
    @Published var stagedPreview = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var hub: GitHubActivity?
    @Published var commitMessage = ""
    @Published var newBranch = ""
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
        selectedFile = nil; selectedCommit = nil; preview = ""; commitMessage = ""; notice = nil
        persist(); refresh()
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
            selectedFile = nil; selectedCommit = nil; preview = ""; commitMessage = ""
            persist(); notice = "已添加 \(repo.name)"
        }
    }
    func removeSelected() {
        guard !busy, let selectedID else { return }
        cancel(); repositories.removeAll { $0.id == selectedID }
        self.selectedID = repositories.first?.id; hub = nil; snapshot = GitSnapshot(); refreshedAt = nil
        selectedFile = nil; selectedCommit = nil; preview = ""; commitMessage = ""
        persist(); notice = "已从列表移除，仓库文件保留。"; refresh()
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
    func refreshIfDue() {
        if refreshedAt == nil || Date().timeIntervalSince(refreshedAt!) > 900 { refresh() }
    }
    func refresh() {
        guard let repo = selected, !busy, enabled else { return }
        start("正在刷新…") { [self] in
            if let id = repo.github {
                let result = try await GitHubActivityService.load(id)
                try Task.checkCancellation()
                hub = result; refreshedAt = .now
                return
            }
            let url = try resolve(repo); let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let result = try await GitService.snapshot(at: url)
            try Task.checkCancellation()
            snapshot = result; refreshedAt = .now
            if !result.files.contains(where: { $0.path == selectedFile }) { selectedFile = nil; preview = "" }
            if let file = currentFile, stagedPreview && !file.staged { stagedPreview = false }
        }
    }
    var nodes: [GitGraphNode] { selected?.github == nil ? snapshot.nodes : (hub?.nodes ?? []) }
    func openProject() {
        if let id = selected?.github, let url = URL(string: "https://github.com/" + id) { NSWorkspace.shared.open(url) }
        else if let repo = selected, let url = try? resolve(repo) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    func openCommit(_ node: GitGraphNode) {
        if let id = selected?.github, let url = URL(string: "https://github.com/" + id + "/commit/" + node.id) { NSWorkspace.shared.open(url) }
        else { previewCommit(node) }
    }
    private func previewCommit(_ node: GitGraphNode) {
        guard !busy, let repo = selected else { return }
        previewTask?.cancel(); let token = UUID(); previewGeneration = token
        selectedCommit = node.id; previewLoading = true; preview = ""
        previewTask = Task {
            do {
                let url = try resolve(repo); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let result = try await GitService.run(["show", "--format=fuller", "--stat", "--patch", "--no-ext-diff", "--no-textconv", node.id, "--"], at: url).checked()
                guard previewGeneration == token else { return }
                preview = result.text
            } catch { if previewGeneration == token { preview = error.localizedDescription } }
            if previewGeneration == token { previewLoading = false }
        }
    }
}
