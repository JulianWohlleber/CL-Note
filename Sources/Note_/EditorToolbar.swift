import SwiftUI
import AppKit

/// Holds a weak reference to the currently active WikilinkTextView so the
/// SwiftUI toolbar can invoke markdown-formatting actions on it.
final class EditorBridge: ObservableObject {
    weak var textView: WikilinkTextView?
}

struct EditorToolbar: View {
    @ObservedObject var bridge: EditorBridge

    var body: some View {
        HStack(spacing: 2) {
            group {
                iconBtn(.bold,       help: "Bold")           { $0.applyBold() }
                iconBtn(.italic,     help: "Italic")         { $0.applyItalic() }
                iconBtn(.strike,     help: "Strikethrough")  { $0.applyStrikethrough() }
            }
            sep()
            group {
                textBtn("H1",        help: "Heading 1")      { $0.applyH1() }
                textBtn("H2",        help: "Heading 2")      { $0.applyH2() }
                textBtn("H3",        help: "Heading 3")      { $0.applyH3() }
            }
            sep()
            group {
                iconBtn(.listBullet, help: "Bullet list")    { $0.applyBulletList() }
                iconBtn(.listNumber, help: "Numbered list")  { $0.applyNumberList() }
                iconBtn(.checkbox,   help: "Task item")      { $0.applyCheckbox() }
            }
            sep()
            group {
                iconBtn(.quote,      help: "Blockquote")     { $0.applyQuote() }
                iconBtn(.inlineCode, help: "Inline code")    { $0.applyInlineCode() }
                iconBtn(.codeBlock,  help: "Code block")     { $0.applyCodeBlock() }
            }
            sep()
            group {
                iconBtn(.link,       help: "Link")           { $0.applyLink() }
                iconBtn(.wikilink,   help: "Wikilink")       { $0.applyWikilink() }
                iconBtn(.hr,         help: "Horizontal rule"){ $0.applyHR() }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(C.bgSide)
        .overlay(Divider().background(C.border), alignment: .bottom)
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 1) { content() }
    }

    private func sep() -> some View {
        Rectangle()
            .fill(C.border)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func iconBtn(_ icon: Icon,
                         help: String,
                         action: @escaping (WikilinkTextView) -> Void) -> some View {
        ToolbarButton(help: help, bridge: bridge, action: action) { hovered in
            icon.view(size: 14, color: hovered ? C.text : C.textDim)
                .frame(width: 26, height: 22)
        }
    }

    @ViewBuilder
    private func textBtn(_ label: String,
                         help: String,
                         action: @escaping (WikilinkTextView) -> Void) -> some View {
        ToolbarButton(help: help, bridge: bridge, action: action) { hovered in
            Text(label)
                .font(F.syneUI(11, weight: .bold))
                .foregroundColor(hovered ? C.text : C.textDim)
                .frame(width: 26, height: 22)
        }
    }
}

private struct ToolbarButton<Label: View>: View {
    let help: String
    let bridge: EditorBridge
    let action: (WikilinkTextView) -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var hovered = false

    var body: some View {
        Button {
            guard let tv = bridge.textView else { return }
            action(tv)
        } label: {
            label(hovered)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hovered ? C.bgHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}
