import Foundation

struct PomodoroSession: Codable, Equatable {
    enum Phase: String, Codable { case idle, focus, rest, finished }
    static let focusDuration: TimeInterval = 25 * 60
    static let restDuration: TimeInterval = 5 * 60
    var cycles = 4
    var completedCycles = 0
    var phase: Phase = .idle
    var deadline: Date?
    var pausedRemaining: TimeInterval?
    var isActive: Bool { phase == .focus || phase == .rest }
    var isPaused: Bool { isActive && deadline == nil }
    var currentCycle: Int { min(cycles, max(1, completedCycles + (phase == .focus ? 1 : 0))) }
    var duration: TimeInterval { phase == .rest ? Self.restDuration : Self.focusDuration }
    var isValid: Bool {
        guard (1...12).contains(cycles), (0...cycles).contains(completedCycles),
            pausedRemaining.map({ $0.isFinite && $0 >= 0 && $0 <= duration }) ?? true else { return false }
        switch phase {
        case .idle: return completedCycles == 0 && deadline == nil && pausedRemaining == nil
        case .finished: return completedCycles == cycles && deadline == nil && pausedRemaining == nil
        case .focus, .rest:
            guard completedCycles < cycles, phase != .rest || completedCycles > 0 else { return false }
            return (deadline != nil && pausedRemaining == nil) || (deadline == nil && pausedRemaining != nil)
        }
    }
    func remaining(at now: Date) -> TimeInterval {
        if let deadline { return max(0, deadline.timeIntervalSince(now)) }
        return pausedRemaining ?? (phase == .finished ? 0 : Self.focusDuration)
    }
    mutating func configure(cycles: Int) {
        guard !isActive else { return }
        self.cycles = min(12, max(1, cycles))
        reset()
    }
    mutating func start(at now: Date) {
        cycles = min(12, max(1, cycles))
        completedCycles = 0; phase = .focus; pausedRemaining = nil
        deadline = now.addingTimeInterval(Self.focusDuration)
    }
    @discardableResult
    mutating func advance(to now: Date) -> Bool {
        let original = self
        // Absolute deadlines keep the timer accurate after a delayed tick or sleep.
        // At most 24 transitions for the supported cycle range; never replay seconds.
        for _ in 0..<24 {
            guard isActive, let boundary = deadline, boundary <= now else { break }
            if phase == .focus {
                completedCycles += 1
                if completedCycles >= cycles {
                    phase = .finished; deadline = nil; pausedRemaining = nil
                } else {
                    phase = .rest; deadline = boundary.addingTimeInterval(Self.restDuration)
                }
            } else {
                phase = .focus; deadline = boundary.addingTimeInterval(Self.focusDuration)
            }
        }
        return original != self
    }
    mutating func pause(at now: Date) {
        advance(to: now)
        guard isActive, deadline != nil else { return }
        pausedRemaining = remaining(at: now); deadline = nil
    }
    mutating func resume(at now: Date) {
        guard isPaused, let pausedRemaining else { return }
        deadline = now.addingTimeInterval(pausedRemaining); self.pausedRemaining = nil
    }
    mutating func reset() {
        phase = .idle; completedCycles = 0; deadline = nil; pausedRemaining = nil
    }
}
