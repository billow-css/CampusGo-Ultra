import Foundation

struct PlacedCourse: Identifiable {
    let event: CourseOccurrence
    let lane: Int
    var lanes: Int
    var id: String { event.id }
}

enum CalendarPlacement {
    static func layout(_ events: [CourseOccurrence]) -> [PlacedCourse] {
        let sorted = events.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        var result: [PlacedCourse] = []
        var cluster: [PlacedCourse] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast
        func flush() {
            let count = laneEnds.count
            result.append(contentsOf: cluster.map { .init(event: $0.event, lane: $0.lane, lanes: count) })
            cluster.removeAll(); laneEnds.removeAll(); clusterEnd = .distantPast
        }
        for event in sorted {
            if event.start >= clusterEnd { flush() }
            let lane = laneEnds.firstIndex { $0 <= event.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(event.end) } else { laneEnds[lane] = event.end }
            cluster.append(.init(event: event, lane: lane, lanes: 1))
            clusterEnd = max(clusterEnd, event.end)
        }
        flush()
        return result
    }
}
