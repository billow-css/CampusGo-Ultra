import Foundation
import Security

struct GitGraphNode: Identifiable {
    let id: String
    let parents: [String]
    let subject: String
    let author: String
    let date: Date
    let refs: String
}
struct GitCommitDetail {
    let message: String
    let files: [File]
    var note: String? = nil

    struct File: Decodable {
        let filename: String
        let patch: String?
        let status: String?
        let additions: Int?
        let deletions: Int?
    }
}
struct GitHubItem: Decodable, Identifiable {
    let id: Int
    let title: String
    let html_url: URL
    let number: Int
    let pull_request: PullMarker?
    struct PullMarker: Decodable {}
}
struct GitHubRun: Decodable, Identifiable {
    let id: Int
    let name: String?
    let status: String
    let conclusion: String?
    let html_url: URL
    let head_branch: String?
    let run_attempt: Int?
    let event: String?
    let created_at: String?
    var failed: Bool { ["failure", "timed_out", "action_required"].contains(conclusion ?? "") }
}
enum GitHubDetailTarget: Identifiable {
    case pull(GitHubItem)
    case issue(GitHubItem)
    case run(GitHubRun)

    var id: String {
        switch self {
        case .pull(let item): return "pr-\(item.number)"
        case .issue(let item): return "issue-\(item.number)"
        case .run(let run): return "ci-\(run.id)"
        }
    }
    var title: String {
        switch self {
        case .pull(let item), .issue(let item): return item.title
        case .run(let run): return run.name ?? "Workflow"
        }
    }
    var label: String {
        switch self {
        case .pull(let item): return "PR #\(item.number)"
        case .issue(let item): return "Issue #\(item.number)"
        case .run(let run): return "CI · \(run.id)"
        }
    }
}

struct GitHubDiscussion: Decodable {
    struct User: Decodable { let login: String }
    struct Branch: Decodable { let ref: String }
    let title: String
    let body: String?
    let state: String
    let user: User?
    let created_at: String?
    let comments: Int?
    let draft: Bool?
    let merged: Bool?
    let head: Branch?
    let base: Branch?
}

struct GitHubComment: Decodable, Identifiable {
    let id: Int
    let user: GitHubDiscussion.User?
    let body: String
    let created_at: String?
}

struct GitHubJob: Decodable, Identifiable {
    struct Step: Decodable, Identifiable {
        let number: Int
        let name: String
        let status: String
        let conclusion: String?
        var id: Int { number }
    }
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let steps: [Step]?
}

enum GitHubRemoteDetail {
    case discussion(GitHubDiscussion, comments: [GitHubComment]?, files: [GitCommitDetail.File]?, warnings: [String])
    case run(GitHubRun, jobs: [GitHubJob], totalJobs: Int)
}

struct GitHubActivity {
    var description = ""
    var nodes: [GitGraphNode] = []
    var pulls: [GitHubItem] = []
    var issues: [GitHubItem] = []
    var runs: [GitHubRun] = []
    var warnings: [String] = []
}
/// Keeps API responses and rate-limit state isolated to the current credential.
actor GitHubActivityService {
    private struct CachedResponse {
        let etag: String
        let data: Data
    }
    private var cache: [URL: CachedResponse] = [:]
    private var retryAt: Date?
    private var token: String?
    private let session = URLSession(configuration: .ephemeral, delegate: GitHubRedirectPolicy(), delegateQueue: nil)

    func load(_ id: String, token: String?, previous: GitHubActivity?) async throws -> GitHubActivity {
        configureToken(token)
        return try await load(id, previous: previous)
    }

    private func configureToken(_ token: String?) {
        if self.token != token {
            self.token = token
            cache.removeAll()
            retryAt = nil
        }
    }

    func commitDetail(repo: String, sha: String, token: String?) async throws -> GitCommitDetail {
        struct Response: Decodable {
            struct Commit: Decodable { let message: String }
            let commit: Commit
            let files: [GitCommitDetail.File]?
        }
        guard Self.identifier(repo) == repo, sha.count == 40,
              sha.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw GitFailure(message: "提交地址无效。")
        }
        configureToken(token)
        let result = try await get(repo + "/commits/" + sha + "?per_page=100", as: Response.self)
        let files = result.files ?? []
        return GitCommitDetail(message: result.commit.message, files: files,
                               note: files.count == 100 ? "大型提交仅预览前 100 个改动文件。" : nil)
    }

    func remoteDetail(repo: String, target: GitHubDetailTarget, token: String?) async throws -> GitHubRemoteDetail {
        guard Self.identifier(repo) == repo else { throw GitFailure(message: "GitHub 仓库名称无效。") }
        configureToken(token)
        switch target {
        case .pull(let item):
            return try await discussion(repo: repo, number: item.number, pull: true)
        case .issue(let item):
            return try await discussion(repo: repo, number: item.number, pull: false)
        case .run(let run):
            struct Jobs: Decodable { let jobs: [GitHubJob]; let total_count: Int }
            let path = repo + "/actions/runs/\(run.id)"
            let current = try await get(path, as: GitHubRun.self)
            let attempt = current.run_attempt.map { "/attempts/\($0)" } ?? ""
            let jobs = try await get(path + attempt + "/jobs?per_page=100", as: Jobs.self)
            return .run(current, jobs: jobs.jobs, totalJobs: jobs.total_count)
        }
    }

    private func discussion(repo: String, number: Int, pull: Bool) async throws -> GitHubRemoteDetail {
        let issuePath = repo + "/issues/\(number)"
        let pullPath = repo + "/pulls/\(number)"
        let discussion = try await get(pull ? pullPath : issuePath, as: GitHubDiscussion.self)
        var warnings: [String] = []
        let comments: [GitHubComment]? = try await section("评论", warnings: &warnings, fallback: nil) {
            try await get(issuePath + "/comments?per_page=30", as: [GitHubComment].self)
        }
        let files: [GitCommitDetail.File]? = if pull {
            try await section("改动文件", warnings: &warnings, fallback: nil) {
                try await get(pullPath + "/files?per_page=100", as: [GitCommitDetail.File].self)
            }
        } else { nil }
        return .discussion(discussion, comments: comments, files: files, warnings: warnings)
    }

    static func identifier(_ input: String) -> String? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String
        if raw.contains("://") {
            guard let url = URL(string: raw), url.scheme == "https", url.host?.lowercased() == "github.com", url.user == nil, url.password == nil else { return nil }
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else { value = raw }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard parts.allSatisfy({ !$0.isEmpty && !$0.contains("..") && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return value.hasSuffix(".git") ? String(value.dropLast(4)) : value
    }
    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try Task.checkCancellation()
        if let retryAt, retryAt > Date() { throw GitHubAPIError.rateLimit(retryAt) }
        guard let url = URL(string: "https://api.github.com/repos/" + path) else {
            throw GitFailure(message: "GitHub 仓库链接无效。")
        }
        let cached = cache[url]
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CampusGo-Ultra", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let cached { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }
        let (bytes, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GitFailure(message: "GitHub 返回了无效响应。") }
        if http.statusCode == 304, let cached { return try JSONDecoder().decode(T.self, from: cached.data) }
        guard (200..<300).contains(http.statusCode) else {
            let error = GitHubAPIError.response(http, body: bytes, authenticated: token != nil)
            if case .rateLimit(let until) = error { retryAt = until }
            throw error
        }
        let decoded = try JSONDecoder().decode(T.self, from: bytes)
        if let etag = http.value(forHTTPHeaderField: "ETag"), bytes.count <= 1_000_000 {
            if cache.count >= 60 && cached == nil { cache.removeAll() }
            cache[url] = CachedResponse(etag: etag, data: bytes)
        } else { cache.removeValue(forKey: url) }
        return decoded
    }
    private func section<T>(_ title: String, warnings: inout [String], fallback: T,
                            read: () async throws -> T) async throws -> T {
        do { return try await read() }
        catch {
            try Task.checkCancellation()
            if let api = error as? GitHubAPIError {
                if case .invalidToken = api { throw api }
                if case .rateLimit = api {
                    let message = api.localizedDescription
                    if !warnings.contains(message) { warnings.append(message) }
                    return fallback
                }
            }
            warnings.append(title + "：" + error.localizedDescription)
            return fallback
        }
    }
    private func load(_ id: String, previous: GitHubActivity?) async throws -> GitHubActivity {
        guard Self.identifier(id) == id else { throw GitFailure(message: "GitHub 仓库名称无效。") }
        struct Repo: Decodable { let description: String? }
        struct Commit: Decodable {
            let sha: String
            let parents: [Parent]
            let commit: Info
            struct Parent: Decodable { let sha: String }
            struct Info: Decodable { let message: String; let author: Author }
            struct Author: Decodable { let name: String; let date: String }
        }
        struct Runs: Decodable { let workflow_runs: [GitHubRun] }
        let repo = try await get(id, as: Repo.self)
        var result = GitHubActivity(); result.description = repo.description ?? ""
        var warnings: [String] = []
        result.nodes = try await section("提交", warnings: &warnings, fallback: previous?.nodes ?? []) {
            let commits: [Commit]
            do { commits = try await get(id + "/commits?per_page=80", as: [Commit].self) }
            catch GitHubAPIError.http(409) { return [] }
            let iso = ISO8601DateFormatter()
            return commits.compactMap { item in
                guard let date = iso.date(from: item.commit.author.date) else { return nil }
                return GitGraphNode(id: item.sha, parents: item.parents.map(\.sha), subject: item.commit.message.components(separatedBy: "\n")[0], author: item.commit.author.name, date: date, refs: "")
            }
        }
        result.pulls = try await section("PR", warnings: &warnings, fallback: previous?.pulls ?? []) {
            try await get(id + "/pulls?state=open&per_page=20&sort=updated&direction=desc", as: [GitHubItem].self)
        }
        result.issues = try await section("Issue", warnings: &warnings, fallback: previous?.issues ?? []) {
            try await get(id + "/issues?state=open&per_page=30&sort=updated&direction=desc", as: [GitHubItem].self).filter { $0.pull_request == nil }
        }
        result.runs = try await section("CI", warnings: &warnings, fallback: previous?.runs ?? []) {
            try await get(id + "/actions/runs?per_page=10", as: Runs.self).workflow_runs
        }
        result.warnings = warnings
        return result
    }
}

private final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        let sameOrigin = url?.scheme == "https" && url?.host == "api.github.com" && (url?.port == nil || url?.port == 443)
        completionHandler(sameOrigin ? request : nil)
    }
}

private enum GitHubAPIError: LocalizedError {
    case rateLimit(Date), invalidToken, forbidden, notFound(Bool), http(Int)

    static func response(_ response: HTTPURLResponse, body: Data, authenticated: Bool) -> Self {
        struct APIMessage: Decodable { let message: String? }
        let status = response.statusCode
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
        let exhausted = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
        let message = (try? JSONDecoder().decode(APIMessage.self, from: body))?.message?.lowercased() ?? ""
        if status == 429 || (status == 403 && (exhausted || retryAfter != nil || message.contains("rate limit"))) {
            let now = Date()
            let reset = exhausted ? response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init) : nil
            let dates = [retryAfter.map { now.addingTimeInterval(max(1, $0)) }, reset.map { Date(timeIntervalSince1970: $0) }]
            let until = dates.compactMap { $0 }.max() ?? now.addingTimeInterval(120)
            return .rateLimit(max(until, now.addingTimeInterval(1)))
        }
        switch status {
        case 401: return .invalidToken
        case 403: return .forbidden
        case 404: return .notFound(authenticated)
        default: return .http(status)
        }
    }
    var errorDescription: String? {
        switch self {
        case .rateLimit(let date): return "GitHub API 已限流，\(date.formatted(date: .abbreviated, time: .shortened)) 后可重试。也可在 Git 设置中添加访问令牌。"
        case .invalidToken: return "GitHub 访问令牌无效或已过期，请在 Git 设置中更新或移除。"
        case .forbidden: return "GitHub 拒绝访问（403）。请检查令牌权限、组织访问策略或网络代理。"
        case .notFound(true): return "找不到仓库或没有访问权限。请检查仓库地址和令牌授权范围。"
        case .notFound(false): return "找不到公开仓库。请检查地址；现有私有仓库可使用有读取权限的访问令牌。"
        case .http(let status): return "GitHub 请求失败（HTTP \(status)）。"
        }
    }
}

enum GitHubTokenKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.campusschedule.mac.github",
        kSecAttrAccount as String: "api.github.com"
    ]
    static func load() throws -> String? {
        var attributes = query
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        attributes[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let bytes = item as? Data, let token = String(data: bytes, encoding: .utf8) else {
            throw GitFailure(message: "钥匙串中的 GitHub 令牌无法读取。")
        }
        return token
    }
    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let values = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            try check(SecItemAdd(attributes as CFDictionary, nil))
        } else { try check(status) }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw GitFailure(message: "无法访问 macOS 钥匙串（\(status)）。") }
    }
}
