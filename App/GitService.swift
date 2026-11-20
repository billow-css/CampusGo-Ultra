import Foundation
import Darwin

struct GitRepository: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var bookmark: Data
    var github: String? = nil
}
struct GitFileChange: Identifiable, Equatable {
    let path: String
    let originalPath: String?
    let index: Character
    let worktree: Character
    var id: String { path }
    var untracked: Bool { index == "?" }
    var staged: Bool { ![" ", "?", "!"].contains(index) }
    var unstaged: Bool { worktree != " " || untracked }
    var conflicted: Bool { index == "U" || worktree == "U" || String([index, worktree]) == "AA" || String([index, worktree]) == "DD" }
    var paths: [String] { [path] + (originalPath.map { [$0] } ?? []) }
    var label: String { conflicted ? "冲突" : untracked ? "新增" : String([index, worktree]).trimmingCharacters(in: .whitespaces) }
}
struct GitCommit: Identifiable, Equatable {
    let id: String
    let shortID: String
    let author: String
    let relativeDate: String
    let subject: String
}
struct GitSnapshot {
    var nodes: [GitGraphNode] = []
    var activityDates: [Date] = []
    var branch = ""
    var tracking = ""
    var files: [GitFileChange] = []
    var branches: [String] = []
    var commits: [GitCommit] = []
    var upstream = ""
    var stagedCount: Int { files.filter(\.staged).count }
    var unstagedCount: Int { files.filter(\.unstaged).count }
    static func status(_ data: Data) -> GitSnapshot {
        var result = GitSnapshot()
        let records = data.split(separator: 0, omittingEmptySubsequences: false)
        var offset = 0
        while offset < records.count {
            let bytes = records[offset]; offset += 1
            if bytes.starts(with: [35, 35, 32]) {
                let line = String(decoding: bytes.dropFirst(3), as: UTF8.self)
                let parts = line.components(separatedBy: "...")
                result.branch = parts[0].replacingOccurrences(of: "No commits yet on ", with: "").replacingOccurrences(of: "Initial commit on ", with: "")
                if parts.count > 1 {
                    result.upstream = parts[1].components(separatedBy: " ")[0]
                    if let begin = line.firstIndex(of: "[") { result.tracking = String(line[begin...]) }
                }
                continue
            }
            guard bytes.count >= 4 else { continue }
            let chars = Array(bytes.prefix(2)).map { Character(UnicodeScalar($0)) }
            let path = String(decoding: bytes.dropFirst(3), as: UTF8.self)
            var original: String?
            if chars.contains("R") || chars.contains("C") {
                if offset < records.count { original = String(decoding: records[offset], as: UTF8.self); offset += 1 }
            }
            result.files.append(GitFileChange(path: path, originalPath: original, index: chars[0], worktree: chars[1]))
        }
        return result
    }
    static func history(_ data: Data) -> [GitCommit] {
        data.split(separator: 0).compactMap { record in
            let parts = String(decoding: record, as: UTF8.self).trimmingCharacters(in: .newlines).split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5, parts[0].count == 40 || parts[0].count == 64 else { return nil }
            return GitCommit(id: parts[0], shortID: parts[1], author: parts[2], relativeDate: parts[3], subject: parts[4])
        }
    }
}
struct GitFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
struct GitOutput {
    let status: Int32
    let data: Data
    let error: String
    let truncated: Bool
    var text: String { String(decoding: data, as: UTF8.self) + (truncated ? "\n\n…内容过长，已截断预览。" : "") }
    func checked() throws -> GitOutput {
        guard status == 0 else { throw GitFailure(message: error.isEmpty ? text : error) }
        return self
    }
}
/// Child processes, pipe draining and process waits always run off the UI thread.
private final class GitProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    func install(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw CancellationError() }
        self.process = process
        try process.run()
    }
    func cancel() {
        lock.lock(); stopped = true; let process = process; lock.unlock()
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
private final class GitPipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private(set) var bytes = Data()
    private(set) var truncated = false
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    private var shouldStop: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func drain(_ handle: FileHandle) {
        defer { try? handle.close() }
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while !shouldStop {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                let remaining = max(0, 2_000_000 - bytes.count)
                bytes.append(contentsOf: buffer.prefix(min(count, remaining)))
                if count > remaining { truncated = true }
            } else if count == 0 { break }
            else if errno == EAGAIN || errno == EINTR {
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                _ = Darwin.poll(&descriptor, 1, 100)
            } else { break }
        }
    }
}
enum GitService {
    static func run(_ arguments: [String], at directory: URL, timeout: TimeInterval = 30) async throws -> GitOutput {
        let box = GitProcessBox()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .userInitiated) {
                try execute(arguments, at: directory, timeout: timeout, box: box)
            }.value
        } onCancel: { box.cancel() }
    }
    private static func execute(_ arguments: [String], at directory: URL, timeout: TimeInterval, box: GitProcessBox) throws -> GitOutput {
        let process = Process()
        // /usr/bin/git is an xcrun shim; use the actual installed tool inside the sandbox.
        let candidates = ["/Library/Developer/CommandLineTools/usr/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw GitFailure(message: "未找到 Git。请先安装 Apple 命令行工具，或将 Xcode 安装到应用程序文件夹。")
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--no-pager", "--literal-pathspecs", "-c", "core.fsmonitor=false"] + arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GCM_INTERACTIVE"] = "Never"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        try box.install(process)
        try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
        let stdout = GitPipeBuffer(), stderr = GitPipeBuffer(), group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { stdout.drain(output.fileHandleForReading); group.leave() }
        group.enter(); DispatchQueue.global().async { stderr.drain(errors.fileHandleForReading); group.leave() }
        let deadline = DispatchWorkItem { box.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
        // Hooks and helpers may retain inherited pipes; never wait indefinitely for them.
        if group.wait(timeout: .now() + 2) == .timedOut { stdout.stop(); stderr.stop(); group.wait() }
        guard !box.cancelled else { throw GitFailure(message: "操作已取消或超时。请检查仓库状态后重试。") }
        return GitOutput(status: process.terminationStatus, data: stdout.bytes,
                         error: String(decoding: stderr.bytes, as: UTF8.self), truncated: stdout.truncated)
    }

    static func snapshot(at url: URL) async throws -> GitSnapshot {
        let status = try await run(["status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"], at: url).checked()
        guard !status.truncated else { throw GitFailure(message: "仓库变更数量过多，暂时无法完整列出。请先在 Git 中整理工作区。") }
        var snapshot = GitSnapshot.status(status.data)
        snapshot.branches = try await run(["for-each-ref", "--format=%(refname:short)", "refs/heads/"], at: url).checked().text.split(separator: "\n").map(String.init)
        let head = try await run(["rev-parse", "--verify", "HEAD"], at: url)
        if head.status == 0 {
            snapshot.commits = GitSnapshot.history(try await run(["log", "-40", "-z", "--format=%H%n%h%n%an%n%ar%n%s"], at: url).checked().data)
        }
        guard head.status == 0 || !snapshot.branches.isEmpty else { return snapshot }
        let graph = try await run(["log", "--all", "--topo-order", "-80", "-z", "--format=%H%n%P%n%an%n%at%n%D%n%s"], at: url).checked()
        snapshot.nodes = graph.data.split(separator: 0).compactMap { record in
            let p = String(decoding: record, as: UTF8.self).trimmingCharacters(in: .newlines).split(separator: "\n", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 6, let timestamp = Double(p[3]) else { return nil }
            return GitGraphNode(id: p[0], parents: p[1].split(separator: " ").map(String.init), subject: p[5], author: p[2], date: Date(timeIntervalSince1970: timestamp), refs: p[4])
        }
        let dates = try await run(["log", "--all", "--since=84.days.ago", "--format=%at"], at: url).checked()
        snapshot.activityDates = dates.text.split(separator: "\n").compactMap { Double($0).map { Date(timeIntervalSince1970: $0) } }
        return snapshot
    }
    static func diff(file: GitFileChange, staged: Bool, at url: URL) async throws -> String {
        if file.untracked {
            return try await Task.detached {
                let path = url.appendingPathComponent(file.path)
                if try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { return "符号链接：\(file.path)" }
                let handle = try FileHandle(forReadingFrom: path)
                defer { try? handle.close() }
                let bytes = try handle.read(upToCount: 262_145) ?? Data()
                if bytes.contains(0) { return "二进制文件，无法显示文本预览。" }
                return "新增文件 · \(file.path)\n\n" + String(decoding: bytes.prefix(262_144), as: UTF8.self) + (bytes.count > 262_144 ? "\n…预览已截断。" : "")
            }.value
        }
        return try await run(["diff", "--no-ext-diff", "--no-textconv", "--unified=4"] + (staged ? ["--cached"] : []) + ["--"] + file.paths, at: url).checked().text
    }
}
