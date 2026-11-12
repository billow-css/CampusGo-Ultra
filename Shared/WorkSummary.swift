import Foundation

struct WorkSummary {
    let pendingTodos: Int
    let todayTodos: Int
    let overdueTodos: Int
    let pendingHomework: Int
    let upcomingHomework: Int
    let overdueHomework: Int
    let nextTodo: TodoItem?
    let nextHomework: HomeworkAssignment?

    static func date(for todo: TodoItem) -> Date? {
        [todo.scheduledAt, todo.deadline].compactMap { $0 }.min()
    }
    init(snapshot: ScheduleSnapshot, now: Date, calendar: Calendar = .current) {
        let todos = snapshot.todos.filter { !$0.isCompleted }
        let assignments = snapshot.homeworkRecords.filter { !$0.isCompleted }
        pendingTodos = todos.count
        todayTodos = todos.filter { task in
            [task.scheduledAt, task.deadline].compactMap { $0 }.contains { calendar.isDate($0, inSameDayAs: now) }
        }.count
        overdueTodos = todos.filter { $0.deadline.map { $0 < now } == true }.count
        pendingHomework = assignments.count
        upcomingHomework = assignments.filter {
            $0.deadline.map { $0 >= now && $0 <= now.addingTimeInterval(86400) } == true
        }.count
        overdueHomework = assignments.filter { $0.deadline.map { $0 < now } == true }.count
        nextTodo = todos.sorted {
            let lhsOverdue = $0.deadline.map { $0 < now } == true
            let rhsOverdue = $1.deadline.map { $0 < now } == true
            if lhsOverdue != rhsOverdue { return lhsOverdue }
            let lhs = Self.date(for: $0) ?? .distantFuture
            let rhs = Self.date(for: $1) ?? .distantFuture
            if lhs != rhs { return lhs < rhs }
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt < $1.createdAt
        }.first
        nextHomework = assignments.sorted {
            if $0.deadline != $1.deadline { return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt < $1.createdAt
        }.first
    }
}
