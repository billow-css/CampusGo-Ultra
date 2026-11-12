import SwiftUI

/// A visible calendar and separate time field avoid editing tiny numeric date segments.
struct SmartDatePicker: View {
    let title: String
    @Binding var selection: Date
    var nextClass: Date?
    @State private var showingCalendar = false

    private func selectDay(_ day: Date) {
        let calendar = Calendar.current
        let clock = calendar.dateComponents([.hour, .minute, .second], from: selection)
        selection = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0,
            second: clock.second ?? 0, of: day) ?? day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Button { showingCalendar.toggle() } label: {
                    Label(selection.formatted(.dateTime.year().month().day().weekday()), systemImage: "calendar")
                }.popover(isPresented: $showingCalendar) {
                    VStack(spacing: 12) {
                        DatePicker("选择日期", selection: Binding(get: { selection }, set: { selectDay($0) }), displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                        Button("完成") { showingCalendar = false }.keyboardShortcut(.defaultAction)
                    }.padding(16).frame(width: 310)
                }
                DatePicker("时间", selection: $selection, displayedComponents: .hourAndMinute)
                    .labelsHidden().frame(width: 105)
            }
            HStack(spacing: 7) {
                Button("今天") { selectDay(Date()) }
                Button("明天") { selectDay(Calendar.current.date(byAdding: .day, value: 1, to: Date())!) }
                Button("一周后") { selectDay(Calendar.current.date(byAdding: .day, value: 7, to: Date())!) }
                if let nextClass { Button("下次上课") { selection = nextClass } }
                Spacer(minLength: 0)
                Button("23:59") {
                    selection = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: selection) ?? selection
                }.help("设置为当天 23:59")
            }.controlSize(.small).buttonStyle(.bordered)
        }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}
