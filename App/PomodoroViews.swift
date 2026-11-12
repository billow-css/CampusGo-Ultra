import SwiftUI
import Combine

@MainActor
final class PomodoroStore: ObservableObject {
    @Published private(set) var session: PomodoroSession
    private let defaults: UserDefaults
    private let key = "pomodoro.session.v1"
    private var ticker: AnyCancellable?
    private var moduleEnabled = true
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(PomodoroSession.self, from: data), saved.isValid {
            session = saved
        } else { session = PomodoroSession() }
        tick()
        startTicker()
    }
    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
    }
    func setModuleEnabled(_ enabled: Bool) {
        moduleEnabled = enabled
        if enabled { tick(); startTicker() }
        else {
            var value = session
            value.pause(at: Date()); session = value; save()
            ticker?.cancel(); ticker = nil
        }
    }
    private func save() { if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: key) } }
    private func tick() {
        var updated = session
        if updated.advance(to: Date()) { session = updated; save() }
    }
    func setCycles(_ count: Int) { var value = session; value.configure(cycles: count); session = value; save() }
    func start() { guard moduleEnabled else { return }; var value = session; value.start(at: Date()); session = value; save() }
    func togglePause() {
        guard moduleEnabled else { return }
        var value = session
        if value.isPaused { value.resume(at: Date()) } else { value.pause(at: Date()) }
        session = value; save()
    }
    func reset() { var value = session; value.reset(); session = value; save() }
}

struct PomodoroCard: View {
    @EnvironmentObject private var timer: PomodoroStore
    let onExpand: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("番茄钟", systemImage: "timer").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onExpand) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("展开专注视图")
            }
            PomodoroDisplay(expanded: false)
            PomodoroControls(expanded: false)
        }.padding(18).frame(maxWidth: .infinity).frame(height: 252)
            .background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(CampusTheme.boardLine) }
    }
}

struct FocusPage: View {
    let onBack: () -> Void
    var backTitle = "返回摘要"
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: onBack) { Label(backTitle, systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Text("专注空间").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }.padding(24)
            Spacer(minLength: 0)
            PomodoroDisplay(expanded: true)
            PomodoroControls(expanded: true).frame(maxWidth: 410)
            Text("每轮专注 25 分钟，轮间休息 5 分钟；最后一轮专注完成后结束。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CampusTheme.board)
    }
}

private struct PomodoroDisplay: View {
    @EnvironmentObject private var timer: PomodoroStore
    let expanded: Bool
    private var label: String {
        if timer.session.isPaused { return "已暂停" }
        switch timer.session.phase {
        case .idle: return "准备专注"
        case .focus: return "专注时间"
        case .rest: return "休息时间"
        case .finished: return "本次专注已完成"
        }
    }
    var body: some View {
        let ink = timer.session.phase == .rest ? CampusTheme.accent : CampusTheme.examAccent
        return TimelineView(.periodic(from: .now, by: 1)) { tick in
            let seconds = max(0, Int(ceil(timer.session.remaining(at: tick.date))))
            let progress = min(1, max(0, 1 - timer.session.remaining(at: tick.date) / timer.session.duration))
            VStack(spacing: expanded ? 22 : 8) {
                Text(label).font(.system(size: expanded ? 18 : 11, weight: .medium)).foregroundStyle(ink)
                if expanded {
                    ZStack {
                        Circle().stroke(ink.opacity(0.12), lineWidth: 7)
                        Circle().trim(from: 0, to: progress).stroke(ink, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        time(seconds, ink: ink)
                    }.frame(width: 280, height: 280)
                } else {
                    time(seconds, ink: ink)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(ink.opacity(0.12))
                            Capsule().fill(ink).frame(width: geometry.size.width * progress)
                        }
                    }.frame(height: 4)
                }
                Text(timer.session.phase == .idle ? "25 分钟专注 · 5 分钟休息" : "第 \(timer.session.currentCycle) / \(timer.session.cycles) 轮")
                    .font(.system(size: expanded ? 14 : 10)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
        }
    }
    private func time(_ seconds: Int, ink: Color) -> some View {
        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: expanded ? 66 : 40, weight: .medium, design: .monospaced))
            .monospacedDigit().foregroundStyle(ink).contentTransition(.identity)
    }
}

private struct PomodoroControls: View {
    @EnvironmentObject private var timer: PomodoroStore
    let expanded: Bool
    var body: some View {
        let ink = timer.session.phase == .rest ? CampusTheme.accent : CampusTheme.examAccent
        return VStack(spacing: expanded ? 18 : 10) {
            if !timer.session.isActive {
                HStack(spacing: 10) {
                    Text("循环次数").font(.system(size: expanded ? 14 : 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button { timer.setCycles(timer.session.cycles - 1) } label: {
                        Image(systemName: "minus").frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    }.disabled(timer.session.cycles <= 1)
                    Text("\(timer.session.cycles) 次").font(.system(size: expanded ? 14 : 11, design: .monospaced)).frame(width: 42)
                    Button { timer.setCycles(timer.session.cycles + 1) } label: {
                        Image(systemName: "plus").frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    }.disabled(timer.session.cycles >= 12)
                }.buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                if timer.session.isActive {
                    Button(timer.session.isPaused ? "继续" : "暂停") { timer.togglePause() }
                        .buttonStyle(.borderedProminent).tint(ink)
                    Button("重置") { timer.reset() }.buttonStyle(.bordered)
                } else {
                    Button(timer.session.phase == .finished ? "再来一组" : "开始专注") { timer.start() }
                        .buttonStyle(.borderedProminent).tint(ink)
                }
                if expanded { Spacer(minLength: 0) }
            }.controlSize(expanded ? .large : .regular)
        }
    }
}

struct PomodoroSettingsView: View {
    @EnvironmentObject private var timer: PomodoroStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("计时配置").font(.title2).fontWeight(.semibold)
            Text("每轮专注 25 分钟，轮间休息 5 分钟。最后一轮结束后直接完成。").foregroundStyle(.secondary)
            Stepper("循环 \(timer.session.cycles) 次", value: Binding(get: { timer.session.cycles }, set: { timer.setCycles($0) }), in: 1...12)
                .disabled(timer.session.isActive).frame(maxWidth: 350)
            if timer.session.isActive {
                Text("计时进行中，重置后可修改循环次数。").font(.caption).foregroundStyle(.secondary)
                Button("重置本次计时") { timer.reset() }
            }
            Text("关闭模块时会暂停并保留当前进度；再次启用后可以手动继续。").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }
}
