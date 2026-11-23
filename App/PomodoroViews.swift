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
    var onSettings: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("番茄钟", systemImage: "timer").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let onSettings {
                    Button(action: onSettings) { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("番茄钟设置")
                }
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
    var navigationVisible: Binding<Bool>? = nil
    @State private var showingSettings = false
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: onBack) { Label(backTitle, systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Text("专注空间").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Button { showingSettings = true } label: { Label("设置", systemImage: "gearshape") }.buttonStyle(.borderless)
            }.padding(24)
            Spacer(minLength: 0)
            PomodoroDisplay(expanded: true)
            PomodoroControls(expanded: true).frame(maxWidth: 410)
            Text("每轮专注 25 分钟，轮间休息 5 分钟；最后一轮专注完成后结束。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CampusTheme.board)
            .onExitCommand(perform: onBack)
            .sheet(isPresented: $showingSettings) {
                VStack(spacing: 0) {
                    PomodoroSettingsView(navigationVisible: navigationVisible)
                    Divider()
                    HStack { Spacer(); Button("完成") { showingSettings = false }.keyboardShortcut(.cancelAction) }.padding(16)
                }.frame(width: 560, height: 650)
            }
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
    var navigationVisible: Binding<Bool>? = nil
    private var focusMinutes: Int { timer.session.cycles * 25 }
    private var restMinutes: Int { max(0, timer.session.cycles - 1) * 5 }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("番茄钟设置").font(.title2).fontWeight(.semibold)
                    Text("安排本次专注节奏，修改后自动保存。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    durationCard("专注", minutes: 25, icon: "flame", ink: CampusTheme.examAccent)
                    durationCard("休息", minutes: 5, icon: "cup.and.saucer", ink: CampusTheme.accent)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("循环轮数").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Stepper(value: Binding(get: { timer.session.cycles }, set: { timer.setCycles($0) }), in: 1...12) {
                            Text("\(timer.session.cycles) 轮").font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
                        }.fixedSize().disabled(timer.session.isActive)
                    }
                    HStack(spacing: 8) {
                        ForEach([1, 2, 4, 8], id: \.self) { count in
                            Button { timer.setCycles(count) } label: {
                                Text("\(count) 轮").font(.system(size: 12, weight: timer.session.cycles == count ? .semibold : .regular))
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .foregroundStyle(timer.session.cycles == count ? CampusTheme.examAccent : Color.primary)
                                    .background(timer.session.cycles == count ? CampusTheme.examAccent.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(timer.session.cycles == count ? CampusTheme.examAccent.opacity(0.45) : .clear) }
                            }.buttonStyle(.plain).disabled(timer.session.isActive)
                        }
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Label("预计 \(duration(focusMinutes + restMinutes))", systemImage: "clock").font(.system(size: 13, weight: .medium))
                        Text("专注 \(focusMinutes) 分钟 · 休息 \(restMinutes) 分钟").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text("轮间自动休息，最后一轮专注完成后结束。可设置 1–12 轮。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if timer.session.isActive {
                        Divider()
                        HStack {
                            Label("\(timer.session.isPaused ? "已暂停" : "计时中") · 第 \(timer.session.currentCycle)/\(timer.session.cycles) 轮", systemImage: timer.session.isPaused ? "pause.circle" : "timer")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Button("重置后调整") { timer.reset() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }.padding(18).settingsCard()
                if let navigationVisible {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: navigationVisible) {
                            Label("在顶栏常驻番茄钟", systemImage: "rectangle.topthird.inset.filled").font(.system(size: 13, weight: .medium))
                        }.toggleStyle(.switch).controlSize(.small)
                        Text("关闭后，从摘要展开时仍会临时显示标签页；退出展开后收起。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(18).settingsCard()
                }
                Label("关闭模块会暂停并保留进度；再次启用后可手动继续。", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color(nsColor: .windowBackgroundColor))
    }
    private func durationCard(_ title: String, minutes: Int, icon: String, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(minutes)").font(.system(size: 29, weight: .semibold, design: .rounded))
                Text("分钟").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(ink.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
    }
    private func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时" + (minutes % 60 == 0 ? "" : " \(minutes % 60) 分钟")
    }
}

private extension View {
    func settingsCard() -> some View {
        background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(CampusTheme.boardLine) }
    }
}
