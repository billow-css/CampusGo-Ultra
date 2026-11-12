import Foundation

/// A timetable scale that preserves readable class heights while shortening breaks.
struct CalendarTimeScale {
    private struct Segment {
        var start: Int
        var end: Int
        var top: Double
        var height: Double
    }
    private var segments: [Segment] = []
    private(set) var height: Double = 0

    init(start: Int, end: Int, periods: [LessonPeriod], occupied: [(Int, Int)] = []) {
        guard end > start else { return }
        let intervals = (periods.map { ($0.startMinute, $0.endMinute) } + occupied)
            .map { (max(start, $0.0), min(end, $0.1)) }.filter { $0.1 > $0.0 }
        let boundaries = Set([start, end] + intervals.flatMap { [$0.0, $0.1] }).sorted()
        for (left, right) in zip(boundaries, boundaries.dropFirst()) {
            let teaching = intervals.contains { $0.0 <= left && $0.1 >= right }
            let minutes = Double(right - left)
            let segmentHeight = teaching ? minutes * 1.05 : min(14, minutes * 0.32)
            segments.append(.init(start: left, end: right, top: height, height: segmentHeight))
            height += segmentHeight
        }
    }

    func position(for minute: Int) -> Double {
        guard let first = segments.first, let last = segments.last else { return 0 }
        if minute <= first.start { return 0 }
        if minute >= last.end { return height }
        guard let segment = segments.first(where: { minute >= $0.start && minute < $0.end }) else { return 0 }
        return segment.top + Double(minute - segment.start) / Double(segment.end - segment.start) * segment.height
    }
}
