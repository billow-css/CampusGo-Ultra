import Foundation

struct HomeworkSubtask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var isCompleted = false
}

struct HomeworkAssignment: Codable, Identifiable, Equatable {
    var id = UUID()
    var number = ""
    var courseKey: String
    var title: String
    var notes = ""
    var deadline: Date?
    var isPinned = false
    var items: [HomeworkSubtask] = []
    var isManuallyCompleted = false
    var createdAt = Date()

    var completedCount: Int { items.filter(\.isCompleted).count }
    var isCompleted: Bool { items.isEmpty ? isManuallyCompleted : items.allSatisfy(\.isCompleted) }

    mutating func setCompleted(_ completed: Bool) {
        isManuallyCompleted = completed
        for index in items.indices { items[index].isCompleted = completed }
    }

    static func isValidNumber(_ number: String) -> Bool {
        let bytes = Array(number.utf8)
        return bytes.count == 5 && bytes[0] == 72 && bytes.dropFirst().allSatisfy { (48...57).contains($0) }
    }

    static func newNumber(excluding used: Set<String>) -> String? {
        let occupied = Set(used.compactMap { isValidNumber($0) ? Int($0.dropFirst()) : nil })
        guard occupied.count < 10_000 else { return nil }
        // Select uniformly among available numbers, with a bounded scan even near exhaustion.
        var offset = Int.random(in: 0..<(10_000 - occupied.count))
        for value in 0..<10_000 where !occupied.contains(value) {
            if offset == 0 { return String(format: "H%04d", value) }
            offset -= 1
        }
        return nil
    }
}

enum HomeworkError: LocalizedError {
    case emptyTitle, missingCourse, emptySubtask, numbersExhausted
    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "请填写作业标题。"
        case .missingCourse: return "请选择课表中的科目。"
        case .emptySubtask: return "请填写每个子作业的标题，或移除空白条目。"
        case .numbersExhausted: return "H0000–H9999 的作业编号已全部使用，无法分配新编号。已有作业仍可编辑。"
        }
    }
}

struct ScheduleDeadline: Identifiable {
    let id: String
    let title: String
    let icon: String
    let deadline: Date
    var homeworkNumber: String?
    var courseKey: String?
    var displayTitle: String { homeworkNumber.map { "#" + $0 + " " + title } ?? title }
}

extension ScheduleSnapshot {
    var homeworkRecords: [HomeworkAssignment] { homework ?? [] }

    var pendingDeadlines: [ScheduleDeadline] {
        let tasks = todos.compactMap { task -> ScheduleDeadline? in
            guard !task.isCompleted, let deadline = task.deadline else { return nil }
            return .init(id: "todo:" + task.id.uuidString, title: task.title, icon: task.icon, deadline: deadline)
        }
        let assignments = homeworkRecords.compactMap { assignment -> ScheduleDeadline? in
            guard !assignment.isCompleted, let deadline = assignment.deadline else { return nil }
            return .init(id: "homework:" + assignment.id.uuidString, title: assignment.title,
                icon: "book.closed", deadline: deadline, homeworkNumber: assignment.number, courseKey: assignment.courseKey)
        }
        return tasks + assignments
    }

    mutating func upsertHomework(_ assignment: HomeworkAssignment) throws {
        var clean = assignment
        clean.title = clean.title.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.notes = clean.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.title.isEmpty else { throw HomeworkError.emptyTitle }
        guard profiles.contains(where: { $0.id == clean.courseKey }) else { throw HomeworkError.missingCourse }
        for index in clean.items.indices {
            clean.items[index].title = clean.items[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.items[index].title.isEmpty else { throw HomeworkError.emptySubtask }
        }
        var assignments = homeworkRecords
        var reserved = Set(usedHomeworkNumbers ?? [])
        reserved.formUnion(assignments.map(\.number))
        reserved.formUnion(profiles.map(\.shortID).filter(HomeworkAssignment.isValidNumber))
        if let index = assignments.firstIndex(where: { $0.id == clean.id }) {
            clean.number = assignments[index].number
            clean.createdAt = assignments[index].createdAt
            assignments[index] = clean
        } else {
            guard let number = HomeworkAssignment.newNumber(excluding: reserved) else { throw HomeworkError.numbersExhausted }
            clean.number = number
            assignments.append(clean)
        }
        reserved.insert(clean.number)
        homework = assignments
        usedHomeworkNumbers = reserved.sorted()
    }

    mutating func toggleHomework(_ id: UUID) {
        guard var assignments = homework, let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        assignments[index].setCompleted(!assignments[index].isCompleted)
        homework = assignments
    }

    mutating func toggleHomeworkSubtask(_ id: UUID, in assignmentID: UUID) {
        guard var assignments = homework, let parent = assignments.firstIndex(where: { $0.id == assignmentID }),
            let child = assignments[parent].items.firstIndex(where: { $0.id == id }) else { return }
        assignments[parent].items[child].isCompleted.toggle()
        homework = assignments
    }

    mutating func removeHomework(_ id: UUID) {
        // Deleted numbers remain reserved so an old reference never points to a new assignment.
        var reserved = Set(usedHomeworkNumbers ?? [])
        reserved.formUnion(homeworkRecords.map(\.number))
        usedHomeworkNumbers = reserved.sorted()
        homework = homeworkRecords.filter { $0.id != id }
    }
}
