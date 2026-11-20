import Foundation

enum SciPeriod: String, Codable, CaseIterable, Identifiable, Hashable {
    case morning = "M", afternoon = "A", night = "N"
    var id: String { rawValue }
    var title: String { switch self { case .morning: return "上午"; case .afternoon: return "下午"; case .night: return "夜间" } }
    var hours: String { switch self { case .morning: return "07:00–12:00"; case .afternoon: return "14:00–19:00"; case .night: return "19:00–次日 02:00" } }
    func interval(on day: Date, calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: day)
        let startHour = self == .morning ? 7 : self == .afternoon ? 14 : 19
        let endHour = self == .morning ? 12 : self == .afternoon ? 19 : 2
        let endDay = self == .night ? calendar.date(byAdding: .day, value: 1, to: day)! : day
        return DateInterval(start: calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day)!,
                            end: calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: endDay)!)
    }
    static func containing(_ date: Date, calendar: Calendar = .current) -> (day: Date, period: SciPeriod)? {
        let day = calendar.startOfDay(for: date)
        let previous = calendar.date(byAdding: .day, value: -1, to: day)!
        for candidate in [previous, day] {
            for period in allCases {
                let interval = period.interval(on: candidate, calendar: calendar)
                if interval.start <= date && date < interval.end { return (candidate, period) }
            }
        }
        return nil
    }
    func next(on day: Date, calendar: Calendar = .current) -> (day: Date, period: SciPeriod) {
        let day = calendar.startOfDay(for: day)
        switch self {
        case .morning: return (day, .afternoon)
        case .afternoon: return (day, .night)
        case .night: return (calendar.date(byAdding: .day, value: 1, to: day)!, .morning)
        }
    }
}

struct SciSlot: Hashable, Identifiable {
    let day: Date
    let period: SciPeriod
    init(day: Date, period: SciPeriod, calendar: Calendar = .current) {
        self.day = calendar.startOfDay(for: day); self.period = period
    }
    init(_ session: SciSession) { self.init(day: session.day, period: session.period) }
    var id: String { String(day.timeIntervalSinceReferenceDate) + "." + period.rawValue }
}

struct SciTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var isCompleted = false
    var originSessionID: String? = nil
}

struct SciSession: Codable, Equatable, Identifiable {
    var id: String
    var day: Date
    var period: SciPeriod
    var tasks: [SciTask] = []
    // Text being composed survives navigation and relaunch, without becoming a scheduled task.
    var draftText = ""
    var completedCount: Int { tasks.filter(\.isCompleted).count }
    var progress: Double { tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count) }
    var isCompleted: Bool { !tasks.isEmpty && completedCount == tasks.count }
    func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        !tasks.isEmpty && !isCompleted && period.interval(on: day, calendar: calendar).end <= now
    }
    func isCurrent(at now: Date, calendar: Calendar = .current) -> Bool {
        let interval = period.interval(on: day, calendar: calendar)
        return interval.start <= now && now < interval.end
    }
}

enum SciError: LocalizedError {
    case invalidData, unavailable, emptyTitle, noPendingTasks, completedTaskToPool
    var errorDescription: String? {
        switch self {
        case .invalidData: return "日程计划数据格式无效或版本不受支持，原数据已保留。"
        case .unavailable: return "这段安排已不存在，请重新选择。"
        case .emptyTitle: return "任务内容不能为空。"
        case .noPendingTasks: return "这段安排没有需要移动的未完成任务。"
        case .completedTaskToPool: return "请先取消任务的完成勾选，再移入待安排池。"
        }
    }
}

struct SciDocument: Codable, Equatable {
    var schemaVersion = 1
    var sessions: [SciSession] = []
    var pool: [SciTask] = []
    var usedIDs: Set<String> = []

    func validate(calendar: Calendar = .current) throws {
        let ids = sessions.map(\.id)
        let tasks = sessions.flatMap(\.tasks) + pool
        guard schemaVersion == 1, Set(ids).count == ids.count,
              Set(tasks.map(\.id)).count == tasks.count,
              tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              pool.allSatisfy({ !$0.isCompleted }), Set(ids).isSubset(of: usedIDs),
              usedIDs.allSatisfy({ id in
                  let bytes = Array(id.utf8)
                  return bytes.count == 8 && bytes[0] == 83 && bytes.dropFirst().allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
              }),
              sessions.allSatisfy({ $0.day.timeIntervalSinceReferenceDate.isFinite }) else { throw SciError.invalidData }
        var slots = Set<String>()
        for session in sessions {
            let key = String(calendar.startOfDay(for: session.day).timeIntervalSinceReferenceDate) + session.period.rawValue
            guard slots.insert(key).inserted else { throw SciError.invalidData }
        }
    }
    func session(on day: Date, period: SciPeriod, calendar: Calendar = .current) -> SciSession? {
        sessions.first { $0.period == period && calendar.isDate($0.day, inSameDayAs: day) }
    }
    func session(_ id: String) -> SciSession? { sessions.first { $0.id == id } }
    private mutating func allocateID() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var id: String
        repeat { id = "S" + String((0..<7).map { _ in alphabet.randomElement()! }) } while usedIDs.contains(id)
        usedIDs.insert(id)
        return id
    }
    @discardableResult mutating func ensureSession(on day: Date, period: SciPeriod, calendar: Calendar = .current) -> String {
        if let existing = session(on: day, period: period, calendar: calendar) { return existing.id }
        let id = allocateID()
        sessions.append(SciSession(id: id, day: calendar.startOfDay(for: day), period: period))
        return id
    }
    mutating func setDraft(_ text: String, session id: String) throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw SciError.unavailable }
        sessions[index].draftText = text
    }
    mutating func commitDraft(session id: String) throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw SciError.unavailable }
        let titles = sessions[index].draftText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        sessions[index].tasks.append(contentsOf: titles.map { SciTask(title: $0) })
        sessions[index].draftText = ""
    }
    mutating func toggleTask(_ taskID: UUID, session id: String) throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              let task = sessions[index].tasks.firstIndex(where: { $0.id == taskID }) else { throw SciError.unavailable }
        sessions[index].tasks[task].isCompleted.toggle()
    }
    mutating func renameTask(_ taskID: UUID, session id: String, title: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SciError.emptyTitle }
        guard let index = sessions.firstIndex(where: { $0.id == id }),
              let task = sessions[index].tasks.firstIndex(where: { $0.id == taskID }) else { throw SciError.unavailable }
        sessions[index].tasks[task].title = title
    }
    mutating func deleteTask(_ taskID: UUID, session id: String) throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw SciError.unavailable }
        sessions[index].tasks.removeAll { $0.id == taskID }
    }
    mutating func addToPool(_ text: String) {
        pool.append(contentsOf: text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { SciTask(title: $0) })
    }
    mutating func takeFromPool(_ taskID: UUID, into id: String) throws {
        guard let slot = sessions.firstIndex(where: { $0.id == id }),
              let task = pool.firstIndex(where: { $0.id == taskID }) else { throw SciError.unavailable }
        sessions[slot].tasks.append(pool.remove(at: task))
    }
    @discardableResult mutating func moveTask(_ taskID: UUID, to destination: SciSlot?, calendar: Calendar = .current) throws -> String? {
        let sourceIndex = sessions.firstIndex { $0.tasks.contains { $0.id == taskID } }
        let poolIndex = pool.firstIndex { $0.id == taskID }
        guard sourceIndex != nil || poolIndex != nil else { throw SciError.unavailable }
        if let destination, let sourceIndex,
           calendar.isDate(sessions[sourceIndex].day, inSameDayAs: destination.day), sessions[sourceIndex].period == destination.period {
            return sessions[sourceIndex].id
        }
        let originalTask: SciTask
        if let sourceIndex { originalTask = sessions[sourceIndex].tasks.first { $0.id == taskID }! }
        else { originalTask = pool[poolIndex!] }
        if destination == nil {
            guard !originalTask.isCompleted else { throw SciError.completedTaskToPool }
            if poolIndex != nil { return nil }
        }
        var task = originalTask
        var sourceID: String?
        if let sourceIndex {
            sourceID = sessions[sourceIndex].id
            if task.originSessionID == nil { task.originSessionID = sourceID }
            sessions[sourceIndex].tasks.removeAll { $0.id == taskID }
        } else { pool.remove(at: poolIndex!) }
        var destinationID: String?
        if let destination {
            let id = ensureSession(on: destination.day, period: destination.period, calendar: calendar)
            let index = sessions.firstIndex { $0.id == id }!
            sessions[index].tasks.append(task)
            destinationID = id
        } else { pool.append(task) }
        if let sourceID { removeEmptySession(sourceID) }
        return destinationID
    }
    mutating func moveToPool(session id: String) throws {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw SciError.unavailable }
        var pending = sessions[index].tasks.filter { !$0.isCompleted }
        guard !pending.isEmpty else { throw SciError.noPendingTasks }
        for task in pending.indices where pending[task].originSessionID == nil { pending[task].originSessionID = id }
        sessions[index].tasks.removeAll { !$0.isCompleted }
        pool.append(contentsOf: pending)
        removeEmptySession(id)
    }
    /// Carry overdue work to the next usable block, skipping blocks that have already ended.
    @discardableResult mutating func postpone(session id: String, at now: Date, calendar: Calendar = .current) throws -> String {
        guard let source = session(id) else { throw SciError.unavailable }
        let pending = source.tasks.filter { !$0.isCompleted }
        guard !pending.isEmpty else { throw SciError.noPendingTasks }
        var target = source.period.next(on: source.day, calendar: calendar)
        // Jump near today before the bounded three-block search (old plans may be years old).
        let today = calendar.startOfDay(for: now)
        if target.day < today {
            if let current = SciPeriod.containing(now, calendar: calendar) { target = current }
            else { target = (today, .morning) }
        }
        while target.period.interval(on: target.day, calendar: calendar).end <= now {
            target = target.period.next(on: target.day, calendar: calendar)
        }
        let targetID: String
        if session(on: target.day, period: target.period, calendar: calendar) == nil && source.completedCount == 0 && source.draftText.isEmpty {
            let index = sessions.firstIndex { $0.id == id }!
            sessions[index].day = target.day; sessions[index].period = target.period
            return id
        } else {
            targetID = ensureSession(on: target.day, period: target.period, calendar: calendar)
        }
        let sourceIndex = sessions.firstIndex { $0.id == id }!
        let targetIndex = sessions.firstIndex { $0.id == targetID }!
        sessions[sourceIndex].tasks.removeAll { !$0.isCompleted }
        sessions[targetIndex].tasks.append(contentsOf: pending)
        removeEmptySession(id)
        return targetID
    }
    mutating func removeEmptySession(_ id: String) {
        sessions.removeAll { $0.id == id && $0.tasks.isEmpty && $0.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    mutating func removeEmptySessions(except retainedID: String? = nil) {
        sessions.removeAll { $0.id != retainedID && $0.tasks.isEmpty && $0.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    @discardableResult mutating func deleteSession(_ id: String) throws -> SciSession {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { throw SciError.unavailable }
        // Reserved IDs deliberately outlive deleted sessions.
        return sessions.remove(at: index)
    }
    @discardableResult mutating func restoreSession(_ session: SciSession, calendar: Calendar = .current) -> String {
        if let existing = self.session(on: session.day, period: session.period, calendar: calendar),
           let index = sessions.firstIndex(where: { $0.id == existing.id }) {
            let occupied = Set(sessions.flatMap(\.tasks).map(\.id) + pool.map(\.id))
            sessions[index].tasks.append(contentsOf: session.tasks.filter { !occupied.contains($0.id) })
            if !session.draftText.isEmpty {
                sessions[index].draftText += (sessions[index].draftText.isEmpty ? "" : "\n") + session.draftText
            }
            return existing.id
        }
        sessions.append(session); usedIDs.insert(session.id)
        return session.id
    }
    func plannedCount(on day: Date, calendar: Calendar = .current) -> Int {
        sessions.filter { calendar.isDate($0.day, inSameDayAs: day) && !$0.tasks.isEmpty }.count
    }
    func ordered(calendar: Calendar = .current) -> [SciSession] {
        sessions.sorted { $0.period.interval(on: $0.day, calendar: calendar).start < $1.period.interval(on: $1.day, calendar: calendar).start }
    }
    func overdue(at now: Date, calendar: Calendar = .current) -> [SciSession] {
        ordered(calendar: calendar).filter { $0.isOverdue(at: now, calendar: calendar) }
    }
    func featured(at now: Date, calendar: Calendar = .current) -> SciSession? {
        let plans = ordered(calendar: calendar).filter { !$0.tasks.isEmpty && !$0.isCompleted }
        return plans.first { $0.isCurrent(at: now, calendar: calendar) }
            ?? plans.first { $0.period.interval(on: $0.day, calendar: calendar).start > now }
            ?? plans.last { $0.isOverdue(at: now, calendar: calendar) }
    }
}
