import Foundation

struct SharedRepository {
    static var groupIdentifier: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "CampusAppGroup") as? String
        return configured.flatMap { !$0.isEmpty && !$0.hasPrefix("$(") ? $0 : nil } ?? "group.com.campusschedule.shared"
    }
    let fileURL: URL
    let isShared: Bool

    init(fileURL: URL, isShared: Bool = false) { self.fileURL = fileURL; self.isShared = isShared }

    static func application() throws -> SharedRepository {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            let shared = SharedRepository(fileURL: url.appendingPathComponent("schedule-v1.json"), isShared: true)
            // macOS can return a URL even if this build is not entitled to write to it.
            // Verify actual access before selecting the group as the application's store.
            if (try? shared.verifyWritableDirectory()) != nil { return shared }
        }
        return try localApplication()
    }

    static func localApplication() throws -> SharedRepository {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return .init(fileURL: support.appendingPathComponent("CampusSchedule/schedule-v1.json"))
    }

    func verifyWritableDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = directory.appendingPathComponent(".campus-write-check-" + UUID().uuidString)
        try Data().write(to: probe, options: .atomic)
        try FileManager.default.removeItem(at: probe)
    }

    static func widget() -> SharedRepository? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else { return nil }
        return .init(fileURL: url.appendingPathComponent("schedule-v1.json"), isShared: true)
    }

    func load() throws -> ScheduleSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Self.decodeBackup(Data(contentsOf: fileURL))
    }

    static func decodeBackup(_ data: Data) throws -> ScheduleSnapshot {
        let snapshot = try JSONDecoder().decode(ScheduleSnapshot.self, from: data)
        guard snapshot.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        return snapshot
    }

    func save(_ snapshot: ScheduleSnapshot) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Retain the prior file, including a damaged file, before replacing it.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.appendingPathExtension("backup")
            if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
            try FileManager.default.copyItem(at: fileURL, to: backup)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
