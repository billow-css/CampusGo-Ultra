import SwiftUI

@MainActor
final class AppearanceStore: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
    }
    enum Accent: String, CaseIterable, Identifiable {
        case blue, teal, green, purple, rose, graphite
        var id: String { rawValue }
        var title: String { switch self {
            case .blue: return "南信大蓝"; case .teal: return "湖水青"; case .green: return "松林绿"
            case .purple: return "鸢尾紫"; case .rose: return "玫瑰红"; case .graphite: return "石墨灰"
        } }
        var color: Color {
            let hex: Int
            switch self { case .blue: hex = 0x00679C; case .teal: hex = 0x167F82; case .green: hex = 0x32754A
                case .purple: hex = 0x7650B5; case .rose: hex = 0xAF416C; case .graphite: hex = 0x4D6071 }
            return Color(nsColor: NSColor(name: "Theme-\(rawValue)") { appearance in
                let lift = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.40 : 0.0
                let r = Double((hex >> 16) & 255) / 255
                let g = Double((hex >> 8) & 255) / 255
                let b = Double(hex & 255) / 255
                return NSColor(srgbRed: r + (1-r)*lift, green: g + (1-g)*lift, blue: b + (1-b)*lift, alpha: 1)
            })
        }
    }
    private let defaults: UserDefaults
    @Published var mode: Mode { didSet { defaults.set(mode.rawValue, forKey: "appearance.mode") } }
    @Published var accent: Accent { didSet { defaults.set(accent.rawValue, forKey: "appearance.accent") } }
    var colorScheme: ColorScheme? { switch mode { case .system: return nil; case .light: return .light; case .dark: return .dark } }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = Mode(rawValue: defaults.string(forKey: "appearance.mode") ?? "") ?? .system
        accent = Accent(rawValue: defaults.string(forKey: "appearance.accent") ?? "") ?? .blue
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @Environment(\.nuistAccent) private var themeAccent
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("外观与主题").font(.title2).fontWeight(.semibold)
                    Text("选择你喜欢的界面，修改后立即生效并自动保存。").font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("界面模式").font(.headline)
                    Picker("界面模式", selection: $appearance.mode) {
                        ForEach(AppearanceStore.Mode.allCases) { mode in Text(mode.title).tag(mode) }
                    }.pickerStyle(.radioGroup).labelsHidden()
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text("强调色").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(AppearanceStore.Accent.allCases) { accent in
                            Button { appearance.accent = accent } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(accent.color).frame(width: 22, height: 22)
                                    Text(accent.title).font(.system(size: 12))
                                    Spacer(minLength: 0)
                                    if appearance.accent == accent { Image(systemName: "checkmark").foregroundStyle(themeAccent) }
                                }.padding(12).frame(maxWidth: .infinity)
                                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                                    .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(appearance.accent == accent ? themeAccent : Color.clear, lineWidth: 1.5) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "ticket").font(.title2).foregroundStyle(themeAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(appearance.accent.title) · \(appearance.mode.title)").font(.headline)
                        Text("主题应用于导航、操作按钮、今日高亮和主应用登机牌。课程保持各自颜色，考试保持橙色。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(themeAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }.padding(24)
        }
    }
}
