import SwiftUI

/// TextEditor consumes Return as a newline rather than submitting a text field.
struct MultilineTextInput: View {
    @Environment(\.nuistAccent) private var ink
    @Binding var text: String
    let placeholder: String
    var height: CGFloat = 100
    @FocusState private var focused: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 13)).scrollContentBackground(.hidden)
                .padding(6).focused($focused)
                .accessibilityLabel(placeholder)
            if text.isEmpty {
                Text(placeholder).font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 13).allowsHitTesting(false)
            }
        }.frame(height: height)
            .background(CampusTheme.board, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(focused ? ink : CampusTheme.boardLine, lineWidth: 1) }
    }
}
