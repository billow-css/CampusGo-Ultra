import SwiftUI

struct WidgetPreviewView: View {
    @Environment(\.nuistAccent) private var themeAccent
    @EnvironmentObject private var store: AppStore
    @State private var large = false
    @State private var sample = false
    @State private var sampleSnapshot = SampleData.make()
    private var preview: ScheduleSnapshot { sample ? sampleSnapshot : store.snapshot }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("桌面小组件").font(.headline)
                Label(store.isSharingEnabled ? "课表共享已就绪" : "系统桌面小组件尚未启用",
                    systemImage: store.isSharingEnabled ? "checkmark.circle" : "info.circle")
                    .font(.caption).foregroundStyle(store.isSharingEnabled ? themeAccent : Color.secondary)
                Text(store.isSharingEnabled
                    ? "在桌面右键 → 编辑小组件，查找 CampusGo Ultra。下方为外观预览。"
                    : "当前本机测试版还需完成开发签名和安装配置，才能在系统桌面添加。下方为外观预览，并非已安装的小组件。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("尺寸", selection: $large) {
                    Text("中号").tag(false)
                    Text("大号").tag(true)
                }.pickerStyle(.segmented).frame(width: 260)
                Toggle("使用示例课程与考试预览", isOn: $sample).font(.caption)
                    .onChange(of: sample) { _, value in if value { sampleSnapshot = SampleData.make() } }
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    WidgetBoard(snapshot: preview, now: timeline.date, compact: !large)
                        .padding(16).frame(width: 360, height: large ? 350 : 170, alignment: .topLeading)
                        .background(CampusTheme.reminderSurface(preview, at: timeline.date))
                        .clipShape(RoundedRectangle(cornerRadius: 19))
                        .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(CampusTheme.boardLine, lineWidth: 1) }
                }
                Text("课程、考试标识、倒计时及提前 7 天的考试矩形提醒，均与主应用使用相同规则。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
