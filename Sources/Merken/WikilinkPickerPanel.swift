import AppKit
import SwiftUI

// MARK: – Data model

final class WikilinkPickerState: ObservableObject {
    @Published var query    = ""
    @Published var selected = 0
    let allTitles: [String]
    var onConfirm: (String) -> Void

    init(titles: [String], onConfirm: @escaping (String) -> Void) {
        self.allTitles = titles
        self.onConfirm = onConfirm
    }

    var filtered: [String] {
        let q = query.lowercased()
        let list = q.isEmpty ? allTitles : allTitles.filter { $0.lowercased().contains(q) }
        return Array(list.prefix(12))
    }

    var selectedTitle: String? {
        let f = filtered
        guard !f.isEmpty, selected < f.count else { return nil }
        return f[selected]
    }

    func moveDown() { selected = min(selected + 1, max(0, filtered.count - 1)) }
    func moveUp()   { selected = max(0, selected - 1) }
    func confirm()  { if let t = selectedTitle { onConfirm(t) } }
}

// MARK: – SwiftUI picker view

struct WikilinkPickerView: View {
    @ObservedObject var state: WikilinkPickerState

    var body: some View {
        VStack(spacing: 0) {
            if state.filtered.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle").font(.caption).foregroundStyle(.secondary)
                    Text(state.query.isEmpty ? "Type to search…" : "Create \"\(state.query)\"")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            } else {
                ForEach(Array(state.filtered.enumerated()), id: \.offset) { idx, title in
                    Button { state.onConfirm(title) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.caption)
                                .foregroundStyle(idx == state.selected ? .white : .secondary)
                            Text(title)
                                .font(.system(size: 13))
                                .foregroundStyle(idx == state.selected ? .white : .primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(idx == state.selected
                            ? Color.accentColor
                            : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

// MARK: – NSPanel wrapper

final class WikilinkPickerPanel: NSObject {
    private let panel: NSPanel
    let state: WikilinkPickerState

    init(titles: [String], onConfirm: @escaping (String) -> Void) {
        state = WikilinkPickerState(titles: titles, onConfirm: onConfirm)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 10),
            styleMask:   [.nonactivatingPanel, .borderless],
            backing:     .buffered,
            defer:       false
        )
        panel.backgroundColor  = .clear
        panel.isOpaque         = false
        panel.hasShadow        = false   // shadow via SwiftUI view
        panel.level            = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init()

        let host = NSHostingView(rootView: WikilinkPickerView(state: state))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show(near screenRect: NSRect, in window: NSWindow) {
        sizeToFit()
        let x = screenRect.minX
        let y = screenRect.minY - panel.frame.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        window.addChildWindow(panel, ordered: .above)
    }

    func reposition(near screenRect: NSRect) {
        sizeToFit()
        let x = screenRect.minX
        let y = screenRect.minY - panel.frame.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func updateQuery(_ q: String) {
        state.query    = q
        state.selected = 0
        sizeToFit()
    }

    func moveDown() { state.moveDown() }
    func moveUp()   { state.moveUp()   }
    func confirm()  { state.confirm()  }
    var selectedTitle: String? { state.selectedTitle }

    func close() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func sizeToFit() {
        let rowH   = 28.0
        let rows   = max(1, Double(state.filtered.count))
        let height = min(rows * rowH + 4, 260.0)
        var f      = panel.frame
        f.size.height = height
        panel.setFrame(f, display: false)
    }
}
