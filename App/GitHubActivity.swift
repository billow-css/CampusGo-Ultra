import Foundation

struct GitGraphNode: Identifiable {
    let id: String
    let parents: [String]
    let subject: String
    let author: String
    let date: Date
    let refs: String
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
    var failed: Bool { ["failure", "timed_out", "action_required"].contains(conclusion ?? "") }
}
struct GitHubActivity {
    var description = ""
    var nodes: [GitGraphNode] = []
    var pulls: [GitHubItem] = []
    var issues: [GitHubItem] = []
    var runs: [GitHubRun] = []
    var warnings: [String] = []
}
enum GitHubActivityService {
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
    private static func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/" + path)!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CampusGo-Ultra", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitFailure(message: "GitHub 返回了无效响应") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 403 || http.statusCode == 429 { throw GitFailure(message: "GitHub 请求受限，请稍后刷新。") }
            if http.statusCode == 404 { throw GitFailure(message: "仓库不可访问。当前支持公开 GitHub 仓库。") }
            throw GitFailure(message: "GitHub 请求失败（\(http.statusCode)）")
        }
        return try JSONDecoder().decode(T.self, from: bytes)
    }
    static func load(_ id: String) async throws -> GitHubActivity {
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
        // Preserve successful sections when Actions is disabled or an empty repo has no commits.
        do {
            let commits = try await get(id + "/commits?per_page=80", as: [Commit].self)
            let iso = ISO8601DateFormatter()
            result.nodes = commits.compactMap { item in
                guard let date = iso.date(from: item.commit.author.date) else { return nil }
                return GitGraphNode(id: item.sha, parents: item.parents.map(\.sha), subject: item.commit.message.components(separatedBy: "\n")[0], author: item.commit.author.name, date: date, refs: "")
            }
        } catch { result.warnings.append("提交：" + error.localizedDescription) }
        do { result.pulls = try await get(id + "/pulls?state=open&per_page=20&sort=updated&direction=desc", as: [GitHubItem].self) }
        catch { result.warnings.append("PR：" + error.localizedDescription) }
        do { result.issues = try await get(id + "/issues?state=open&per_page=30&sort=updated&direction=desc", as: [GitHubItem].self).filter { $0.pull_request == nil } }
        catch { result.warnings.append("Issue：" + error.localizedDescription) }
        do { result.runs = try await get(id + "/actions/runs?per_page=10", as: Runs.self).workflow_runs }
        catch { result.warnings.append("CI：" + error.localizedDescription) }
        try Task.checkCancellation()
        return result
    }
}
