import SwiftUI

struct GoSciPage: View {
    @EnvironmentObject private var planner: GoSciStore
    @State private var weekOffset = 0
    @State private var selection: SciSlot?
    @State private var inputFocusRequest = 0
    @FocusState private var selectionFocused: Bool
    @StateObject private var keyboardScope = SciKeyboardScope()
    private let initialID: String?
    private let calendar = Calendar.current
    init(selectedID: String? = nil, editing: Bool = false) { initialID = selectedID }
    private var selectedSession: SciSession? { selection.flatMap { planner.session(at: $0) } }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            workspace(now: tick.date)
        }
        .background(SciTheme.background)
        .tint(SciTheme.green).environment(\.nuistAccent, SciTheme.green)
        .focusable().focusEffectDisabled().focused($selectionFocused)
        .background(SciKeyboardAnchor(scope: keyboardScope).frame(width: 0, height: 0))
        .onKeyPress(characters: CharacterSet(charactersIn: "\u{7f}\u{8}"), phases: .down) { press in
            guard press.modifiers.isEmpty, selectionFocused, !keyboardScope.isEditingText, let session = selectedSession else { return .ignored }
            planner.deleteSession(session.id)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { _ in
            guard selection != nil, !keyboardScope.isEditingText else { return .ignored }
            inputFocusRequest += 1
            return .handled
        }
        .onExitCommand(perform: deselect)
        .onAppear {
            if let initialID, let session = planner.document.session(initialID) { select(SciSlot(session)) }
        }
        .onDisappear { planner.releaseSelection() }
        .alert("Agenda", isPresented: Binding(get: { planner.errorMessage != nil }, set: { if !$0 { planner.errorMessage = nil } })) {
            Button("好", role: .cancel) { planner.errorMessage = nil }
        } message: { Text(planner.errorMessage ?? "") }
    }
    private func workspace(now: Date) -> some View {
        let monday = calendar.date(byAdding: .day, value: weekOffset * 7, to: ScheduleFormat.monday(containing: now))!
        return VStack(spacing: 16) {
            AgendaNowStrip(now: now, onLocate: { select(SciSlot($0), revealWeek: true) })
            if let removed = planner.deletedSession {
                HStack(spacing: 10) {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                    Text("已删除 " + removed.day.formatted(.dateTime.month().day()) + " " + removed.period.title + " 的安排").font(.system(size: 12))
                    Spacer()
                    Button("撤销") {
                        if let id = planner.undoDelete(), let session = planner.document.session(id) { select(SciSlot(session), revealWeek: true) }
                    }.buttonStyle(.borderless)
                    Button { planner.dismissUndo() } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).help("关闭提示")
                }.padding(.horizontal, 14).padding(.vertical, 10).sciCard()
            }
            if planner.loadFailed {
                Label("日程数据暂时无法读取，原内容已保留。", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 16) {
                        AgendaWeekMatrix(monday: monday, now: now, selection: selection, weekOffset: $weekOffset,
                            onToday: selectToday, onSelect: { select($0) }, onReveal: { select(SciSlot($0), revealWeek: true) })
                        AgendaPoolPanel(selection: selection, onDeselect: deselect)
                            .frame(minHeight: 140, maxHeight: .infinity)
                    }.frame(minWidth: 510, maxWidth: .infinity, maxHeight: .infinity)
                    AgendaTaskPanel(slot: selection, now: now, focusRequest: inputFocusRequest, onDeselect: deselect,
                        onToday: selectToday, onPostpone: { id in
                            if let moved = planner.postpone(id), let session = planner.document.session(moved) { select(SciSlot(session), revealWeek: true) }
                        })
                        .frame(width: 360).frame(maxHeight: .infinity)
                }.frame(maxHeight: .infinity)
            }
        }.padding(20)
            .onChange(of: weekOffset) { _, _ in
                if let selection {
                    let end = calendar.date(byAdding: .day, value: 7, to: monday)!
                    if selection.day < monday || selection.day >= end { deselect() }
                }
            }
    }
    private func select(_ slot: SciSlot, revealWeek: Bool = false) {
        planner.releaseSelection()
        if revealWeek {
            weekOffset = (calendar.dateComponents([.day], from: ScheduleFormat.monday(containing: .now), to: ScheduleFormat.monday(containing: slot.day)).day ?? 0) / 7
        }
        selection = slot
        selectionFocused = true
        if planner.session(at: slot)?.tasks.isEmpty != false { inputFocusRequest += 1 }
    }
    private func selectToday() {
        let now = Date()
        if let current = SciPeriod.containing(now) { select(SciSlot(day: current.day, period: current.period), revealWeek: true); return }
        let day = calendar.startOfDay(for: now)
        let next = SciPeriod.allCases.first { $0.interval(on: day).start > now } ?? .morning
        select(SciSlot(day: day, period: next), revealWeek: true)
    }
    private func deselect() {
        planner.releaseSelection()
        selection = nil
        selectionFocused = false
    }
}

@MainActor
private final class SciKeyboardScope: ObservableObject {
    weak var window: NSWindow?
    var isEditingText: Bool { window?.firstResponder is NSTextView || window?.firstResponder is NSTextField }
}
private struct SciKeyboardAnchor: NSViewRepresentable {
    let scope: SciKeyboardScope
    func makeNSView(context: Context) -> AnchorView { AnchorView(scope: scope) }
    func updateNSView(_ view: AnchorView, context: Context) { scope.window = view.window }
    final class AnchorView: NSView {
        let scope: SciKeyboardScope
        init(scope: SciKeyboardScope) { self.scope = scope; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scope.window = window }
    }
}

private struct AgendaNowStrip: View {
    @EnvironmentObject private var planner: GoSciStore
    let now: Date
    let onLocate: (SciSession) -> Void
    var body: some View {
        let session = planner.document.featured(at: now)
        return HStack(spacing: 16) {
            Image(systemName: "leaf.fill").font(.system(size: 22)).foregroundStyle(SciTheme.green)
                .frame(width: 48, height: 48).background(SciTheme.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 6) {
                Text(session.map { $0.isCurrent(at: now) ? "正在进行" : $0.isOverdue(at: now) ? "待调整的安排" : "下一段安排" } ?? "留一点时间，给想做的事")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(SciTheme.green)
                Text(session?.tasks.first(where: { !$0.isCompleted })?.title ?? "选一个时段，开始安排")
                    .font(.system(size: 21, weight: .semibold)).lineLimit(1)
                Text(session.map { $0.day.formatted(.dateTime.month().day().weekday()) + " · " + $0.period.title + " " + $0.period.hours } ?? "学习、工作与生活，都可以从一件小事开始。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let session {
                VStack(alignment: .trailing, spacing: 7) {
                    Text("\(session.completedCount) / \(session.tasks.count)").font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                    SciProgressBar(value: session.progress).frame(width: 104)
                }.padding(.horizontal, 10)
                Button { onLocate(session) } label: { Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .medium)).frame(width: 32, height: 32) }
                    .buttonStyle(.plain).foregroundStyle(SciTheme.green).background(SciTheme.green.opacity(0.08), in: Circle()).help("在周历中定位这段安排")
            }
        }.padding(.horizontal, 20).padding(.vertical, 16)
            .background(LinearGradient(colors: [SciTheme.green.opacity(0.065), SciTheme.board], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(SciTheme.green.opacity(0.15)) }
    }
}

private struct AgendaWeekMatrix: View {
    @EnvironmentObject private var planner: GoSciStore
    let monday: Date
    let now: Date
    let selection: SciSlot?
    @Binding var weekOffset: Int
    let onToday: () -> Void
    let onSelect: (SciSlot) -> Void
    let onReveal: (SciSession) -> Void
    @State private var showingOverdue = false
    private let calendar = Calendar.current
    private var days: [Date] { (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! } }
    private func width(_ day: Date) -> CGFloat { calendar.isDate(day, inSameDayAs: now) ? 160 : 36 }
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(monday.formatted(.dateTime.month().day())) — \(days[6].formatted(.dateTime.month().day()))").font(.system(size: 15, weight: .semibold))
                    Text("三时段计划").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 26, height: 26) }.help("上一周")
                Button("今天", action: onToday).font(.system(size: 11, weight: .medium)).padding(.horizontal, 6)
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 26, height: 26) }.help("下一周")
            }.buttonStyle(.plain)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 28, height: 42)
                    ForEach(days, id: \.self) { day in
                        let today = calendar.isDate(day, inSameDayAs: now)
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 10))
                            Text(day.formatted(.dateTime.day())).font(.system(size: 13, weight: today ? .semibold : .medium))
                        }.foregroundStyle(today ? SciTheme.green : Color.secondary).frame(width: width(day), height: 42)
                            .background(today ? SciTheme.green.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                ForEach(SciPeriod.allCases) { period in
                    HStack(spacing: 8) {
                        Text(period.rawValue).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(SciTheme.green)
                            .frame(width: 28, height: 36).help(period.title + " · " + period.hours)
                        ForEach(days, id: \.self) { day in
                            let slot = SciSlot(day: day, period: period)
                            let session = planner.session(at: slot)
                            AgendaMatrixCell(slot: slot, session: session, isToday: calendar.isDate(day, inSameDayAs: now), isSelected: selection == slot, now: now) { onSelect(slot) }
                                .frame(width: width(day))
                                .contextMenu {
                                    Button("选择时段") { onSelect(slot) }
                                    if let session {
                                        Button("顺延未完成项") {
                                            if let id = planner.postpone(session.id), let moved = planner.document.session(id) { onReveal(moved) }
                                        }.disabled(session.isCompleted || session.tasks.isEmpty)
                                        Button("未完成项移入待安排") { planner.toPool(session.id) }.disabled(session.isCompleted || session.tasks.isEmpty)
                                        Divider()
                                        Button("删除整段安排", role: .destructive) { planner.deleteSession(session.id) }
                                    }
                                }
                        }
                    }
                }
            }.frame(maxWidth: .infinity)
            HStack(spacing: 10) {
                let overdue = planner.document.overdue(at: now)
                if overdue.isEmpty {
                    Text("点击选择 · 拖放安排").font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Button { showingOverdue = true } label: {
                        Label("\(overdue.count) 段待调整", systemImage: "exclamationmark.circle.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                    }.buttonStyle(.plain).popover(isPresented: $showingOverdue) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("未完成的安排").font(.system(size: 14, weight: .semibold))
                                ForEach(overdue) { session in
                                    Button { showingOverdue = false; onReveal(session) } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(session.day.formatted(.dateTime.month().day()) + " · " + session.period.title).font(.system(size: 11)).foregroundStyle(.secondary)
                                                Text(session.tasks.first(where: { !$0.isCompleted })?.title ?? "未完成任务").font(.system(size: 13)).lineLimit(2)
                                            }
                                            Spacer()
                                            Image(systemName: "arrow.up.right").foregroundStyle(SciTheme.green)
                                        }.padding(10).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(18)
                        }.frame(width: 320, height: min(360, CGFloat(overdue.count * 75 + 60)))
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("少")
                    ForEach([0, 1, 3, 5, 7], id: \.self) { count in RoundedRectangle(cornerRadius: 2).fill(SciTheme.activityColor(count)).frame(width: 8, height: 8) }
                    Text("多")
                }.font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }.padding(18).sciCard()
    }
}

private struct AgendaMatrixCell: View {
    @EnvironmentObject private var planner: GoSciStore
    let slot: SciSlot
    let session: SciSession?
    let isToday: Bool
    let isSelected: Bool
    let now: Date
    let onSelect: () -> Void
    @State private var hovered = false
    @State private var targeted = false
    private var borderColor: Color {
        if targeted || isSelected { return SciTheme.green }
        return hovered ? SciTheme.green.opacity(0.5) : CampusTheme.boardLine
    }
    private var tooltip: String {
        let base = slot.day.formatted(.dateTime.month().day().weekday()) + " · " + slot.period.hours
        guard let session else { return base + " · 点击安排" }
        return base + " · \(session.tasks.count) 项任务，\(session.completedCount) 项完成"
    }
    var body: some View {
        Button(action: onSelect) { cellContent }
            .buttonStyle(.plain).onHover { hovered = $0 }
            .dropDestination(for: String.self) { payloads, _ in
                let accepted = planner.acceptDrop(payloads, to: slot)
                if accepted { onSelect() }
                return accepted
            } isTargeted: { targeted = $0 }
            .help(tooltip).accessibilityLabel(tooltip)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    private var cellContent: some View {
        HStack(spacing: 6) {
            if isToday, let session {
                Text(verbatim: "#" + session.id).font(.system(size: 9, weight: .semibold, design: .monospaced)).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(session.tasks.count) 项").font(.system(size: 10, weight: .medium))
            }
        }.padding(.horizontal, isToday ? 10 : 0).frame(maxWidth: .infinity).frame(height: 36)
            .foregroundStyle(SciTheme.activityText(session?.tasks.count ?? 0))
            .background(SciTheme.activityColor(session?.tasks.count ?? 0), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(borderColor, lineWidth: targeted || isSelected ? 2 : 1) }
            .scaleEffect(targeted ? 1.035 : 1).contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct AgendaTaskPanel: View {
    @EnvironmentObject private var planner: GoSciStore
    let slot: SciSlot?
    let now: Date
    let focusRequest: Int
    let onDeselect: () -> Void
    let onToday: () -> Void
    let onPostpone: (String) -> Void
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let slot { selectedContent(slot) }
            else {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "rectangle.grid.3x3").font(.system(size: 31, weight: .light)).foregroundStyle(SciTheme.green.opacity(0.75))
                    Text("选一段时间").font(.system(size: 20, weight: .semibold))
                    Text("在左侧点一个色块，\n任务会显示在这里。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                    Button("安排当前时段", action: onToday).buttonStyle(.bordered).controlSize(.small).padding(.top, 3)
                }.frame(maxWidth: .infinity)
                Spacer()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).sciCard()
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? SciTheme.green : .clear, lineWidth: 2) }
            .dropDestination(for: String.self) { payloads, _ in
                guard let slot else { return false }
                return planner.acceptDrop(payloads, to: slot)
            } isTargeted: { targeted = $0 && slot != nil }
    }
    private func selectedContent(_ slot: SciSlot) -> some View {
        let session = planner.session(at: slot)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("时段安排").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if let session {
                        Menu {
                            Button("顺延未完成项") { onPostpone(session.id) }.disabled(session.isCompleted || session.tasks.isEmpty)
                            Button("未完成项移入待安排") { planner.toPool(session.id) }.disabled(session.isCompleted || session.tasks.isEmpty)
                            Divider()
                            Button("删除整段安排", role: .destructive) { planner.deleteSession(session.id) }
                        } label: { Image(systemName: "ellipsis").padding(4) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                    Button(action: onDeselect) { Image(systemName: "xmark").font(.system(size: 10)).padding(4) }.buttonStyle(.plain).foregroundStyle(.secondary).help("取消选择（Esc）")
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(slot.day.formatted(.dateTime.month().day().weekday())).font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Text(slot.period.rawValue).font(.system(size: 22, weight: .medium, design: .rounded)).foregroundStyle(SciTheme.green)
                }
                HStack {
                    Text(slot.period.title + " · " + slot.period.hours).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if session?.isOverdue(at: now) == true { Label("逾期", systemImage: "exclamationmark.circle.fill").font(.system(size: 10)).foregroundStyle(.orange) }
                }
                if let session {
                    HStack {
                        SciIDBadge(id: session.id)
                        Spacer()
                        Text("\(session.completedCount)/\(session.tasks.count) 完成").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    SciProgressBar(value: session.progress)
                }
            }.padding(20)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    if let session, !session.tasks.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(session.tasks) { task in AgendaTaskRow(task: task, session: session, onDeselect: onDeselect).id(task.id) }
                        }.padding(.horizontal, 14).padding(.vertical, 10)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("从一件小事开始").font(.system(size: 15, weight: .medium))
                            Text("在下方输入任务，回车添加。\n也可以从待安排池拖一项进来。")
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                    }
                }.onChange(of: session?.tasks.count ?? 0) { old, new in
                    if new > old, let last = planner.session(at: slot)?.tasks.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }.frame(maxHeight: .infinity)
            VStack(spacing: 8) {
                AgendaQuickEntry(text: planner.inputBinding(at: slot), placeholder: "添加任务，回车继续…", autoFocus: session?.tasks.isEmpty != false,
                    focusRequest: focusRequest, onAdd: { planner.addTasks(at: slot) }, onCancel: onDeselect)
                HStack {
                    Image(systemName: "checkmark.circle").foregroundStyle(SciTheme.green)
                    Text("自动保存").foregroundStyle(.secondary)
                    Spacer()
                    Text("Esc 取消选择").foregroundStyle(.tertiary)
                }.font(.system(size: 9))
            }.padding(16).background(SciTheme.green.opacity(0.025))
        }.id(slot.id)
    }
}

private struct AgendaTaskRow: View {
    @EnvironmentObject private var planner: GoSciStore
    let task: SciTask
    let session: SciSession
    let onDeselect: () -> Void
    @State private var text: String
    @State private var hovered = false
    @FocusState private var focused: Bool
    init(task: SciTask, session: SciSession, onDeselect: @escaping () -> Void) {
        self.task = task; self.session = session; self.onDeselect = onDeselect
        _text = State(initialValue: task.title)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9)).foregroundStyle(.tertiary)
                .frame(width: 12, height: 20).draggable(GoSciStore.dragPrefix + task.id.uuidString).help("拖到其他时段，或移回待安排")
            Button { planner.toggle(task, in: session) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").font(.system(size: 17)).foregroundStyle(task.isCompleted ? SciTheme.green : Color.secondary)
            }.buttonStyle(.plain).padding(.top, 1).accessibilityLabel(task.isCompleted ? "标记未完成" : "完成任务")
            TextField("任务", text: $text, axis: .vertical).textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4)
                .strikethrough(task.isCompleted && !focused).foregroundStyle(task.isCompleted && !focused ? Color.secondary : Color.primary).focused($focused)
                .onChange(of: text) { _, value in
                    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          planner.document.session(session.id)?.tasks.contains(where: { $0.id == task.id }) == true else { return }
                    planner.edit { try $0.renameTask(task.id, session: session.id, title: value) }
                }
                .onChange(of: task.title) { _, value in if !focused { text = value } }
                .onChange(of: focused) { _, active in if !active && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = task.title } }
                .onSubmit { focused = false }.onExitCommand(perform: onDeselect)
            Menu {
                Button("移回待安排") { _ = planner.moveTask(task.id, to: nil) }.disabled(task.isCompleted)
                Button("删除任务", role: .destructive) {
                    planner.edit { try $0.deleteTask(task.id, session: session.id); $0.removeEmptySession(session.id) }
                }
            } label: { Image(systemName: "ellipsis").font(.system(size: 10)).padding(3) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().opacity(hovered ? 1 : 0.45)
        }.padding(.horizontal, 7).padding(.vertical, 11)
            .background(hovered ? Color.primary.opacity(0.025) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.045)).frame(height: 0.5).padding(.horizontal, 7) }
            .onHover { hovered = $0 }
    }
}

private struct AgendaPoolPanel: View {
    @EnvironmentObject private var planner: GoSciStore
    let selection: SciSlot?
    let onDeselect: () -> Void
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Label("待安排", systemImage: "tray").font(.system(size: 14, weight: .semibold))
                Text("\(planner.document.pool.count)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(SciTheme.green)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(SciTheme.green.opacity(0.09), in: Capsule())
                Spacer()
                Text("拖到色块，或点 + 安排").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            AgendaQuickEntry(text: $planner.poolInput, placeholder: "先记下一件想做的事…", onAdd: { planner.addPoolInput() }, onCancel: onDeselect)
            ScrollView {
                if planner.document.pool.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "tray").foregroundStyle(SciTheme.green.opacity(0.6))
                        Text("暂时排不开的任务，可以先放在这里。").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 18)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(planner.document.pool) { task in
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary)
                                Text(task.title).font(.system(size: 12)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                if let selection {
                                    Button { _ = planner.moveTask(task.id, to: selection) } label: { Image(systemName: "plus.circle").font(.system(size: 16)).foregroundStyle(SciTheme.green) }
                                        .buttonStyle(.plain).help("加入选中时段")
                                }
                                Menu {
                                    if let selection { Button("加入选中时段") { _ = planner.moveTask(task.id, to: selection) } }
                                    Button("删除任务", role: .destructive) { planner.edit { $0.pool.removeAll { $0.id == task.id } } }
                                } label: { Image(systemName: "ellipsis").font(.system(size: 10)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }.padding(.horizontal, 11).padding(.vertical, 11)
                                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                                .draggable(GoSciStore.dragPrefix + task.id.uuidString)
                        }
                    }
                }
            }.frame(minHeight: 0, maxHeight: .infinity)
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).sciCard()
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? SciTheme.green : .clear, lineWidth: 2) }
            .dropDestination(for: String.self) { payloads, _ in planner.acceptDrop(payloads, to: nil) } isTargeted: { targeted = $0 }
    }
}

private struct AgendaQuickEntry: View {
    @Binding var text: String
    let placeholder: String
    var autoFocus = false
    var focusRequest = 0
    let onAdd: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(SciTheme.green.opacity(0.7))
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                .onSubmit(add).onExitCommand(perform: onCancel)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: add) { Image(systemName: "arrow.turn.down.left").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(SciTheme.green).help("回车添加")
            }
        }.padding(.horizontal, 12).padding(.vertical, 11)
            .background(SciTheme.green.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? SciTheme.green.opacity(0.6) : CampusTheme.boardLine) }
            .onAppear { if autoFocus { focused = true } }
            .onChange(of: focusRequest) { _, _ in focused = true }
    }
    private func add() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onAdd(); focused = true
    }
}

struct AgendaSettingsView: View {
    @EnvironmentObject private var planner: GoSciStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Agenda 设置", systemImage: "leaf.fill").font(.title2).fontWeight(.semibold).foregroundStyle(SciTheme.green)
                    Text("给标签页取一个喜欢的名字，修改后立即生效并保存。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("顶栏名称").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(planner.customNavigationTitle.count)/120").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    TextField("Agenda", text: Binding(get: { planner.customNavigationTitle }, set: { planner.setNavigationTitle($0) }))
                        .textFieldStyle(.roundedBorder).font(.system(size: 14))
                    HStack {
                        Text("留空使用 Agenda，长名称会在顶栏自动滚动显示。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") { planner.setNavigationTitle("") }.buttonStyle(.borderless)
                            .disabled(planner.customNavigationTitle.isEmpty)
                    }
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "leaf.fill")
                        ScrollingTabTitle(title: planner.navigationTitle, selected: true)
                        Spacer()
                        Text("顶栏预览").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.foregroundStyle(SciTheme.green).padding(12)
                        .background(SciTheme.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }.padding(18).sciCard()
            }.padding(24)
        }.tint(SciTheme.green).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct GoSciSummaryCard: View {
    @EnvironmentObject private var planner: GoSciStore
    let onOpen: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            let session = planner.document.featured(at: tick.date)
            let overdue = planner.document.overdue(at: tick.date).count
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Agenda", systemImage: "leaf.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(SciTheme.green)
                    Spacer()
                    if let session { SciIDBadge(id: session.id) }
                }
                if planner.loadFailed {
                    Text("日程计划读取失败，原数据已保留。").font(.system(size: 12)).foregroundStyle(.orange)
                } else if let session {
                    Text(session.tasks.first(where: { !$0.isCompleted })?.title ?? "日程安排").font(.system(size: 20, weight: .semibold)).lineLimit(2)
                    Text((session.isCurrent(at: tick.date) ? "正在进行 · " : session.isOverdue(at: tick.date) ? "逾期未完成 · " : "下一段 · ") + session.day.formatted(.dateTime.month().day()) + " " + session.period.rawValue)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    SciProgressBar(value: session.progress)
                    Text("\(session.completedCount)/\(session.tasks.count) 项已完成").font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("给探索留一段时间").font(.system(size: 20, weight: .semibold))
                    Text("用 M / A / N 三段安排任务，随时调整。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack {
                    if overdue > 0 { Label("\(overdue) 段待处理", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                    Text("池中 \(planner.document.pool.count) 项").foregroundStyle(.secondary)
                    Spacer()
                    Button("打开", action: onOpen).buttonStyle(.bordered).tint(SciTheme.green)
                }.font(.system(size: 10)).controlSize(.small)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading).sciCard()
        }
    }
}

private struct SciIDBadge: View {
    let id: String
    var body: some View {
        Text("#" + id).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(SciTheme.green)
            .padding(.horizontal, 8).padding(.vertical, 5).background(SciTheme.green.opacity(0.11), in: RoundedRectangle(cornerRadius: 5))
            .textSelection(.enabled)
    }
}

private struct SciProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SciTheme.green.opacity(0.13))
                Capsule().fill(SciTheme.green).frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }.frame(height: 5).accessibilityElement().accessibilityLabel("任务进度").accessibilityValue("\(Int(value * 100))%")
    }
}

private extension View {
    func sciCard() -> some View {
        background(SciTheme.board, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(CampusTheme.boardLine) }
    }
}
