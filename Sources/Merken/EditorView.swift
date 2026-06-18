import SwiftUI
import AppKit

/// Editor body — just the text view, no toolbar (toolbar is in the shared band).
struct EditorView: View {
    @EnvironmentObject var store: NoteStore
    let note: Note
    let bridge: EditorBridge

    var body: some View {
        NoteEditorRepresentable(note: note, bridge: bridge)
            .environmentObject(store)
            .background(C.bg)
    }
}

struct NoteEditorRepresentable: NSViewRepresentable {
    let note: Note
    let bridge: EditorBridge
    @EnvironmentObject var store: NoteStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store, note: note) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll            = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = C.bgNS
        scroll.hasVerticalScroller   = true
        scroll.hasHorizontalScroller = false
        scroll.autoresizingMask      = [.width, .height]

        // Scrollbar styling
        scroll.scrollerStyle    = .overlay
        scroll.verticalScroller?.controlSize = .mini

        // Build text stack with custom storage
        let storage   = WikilinkTextStorage()
        let layout    = NSLayoutManager()
        storage.addLayoutManager(layout)

        let container = NSTextContainer(containerSize: NSSize(
            width:  scroll.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let tv = WikilinkTextView(frame: .zero, textContainer: container)
        tv.isEditable              = true
        tv.isRichText              = false
        tv.allowsUndo              = true
        tv.font                    = F.serif(15)
        tv.textColor               = C.textNS
        tv.backgroundColor         = C.bgNS
        tv.insertionPointColor     = C.textNS
        tv.selectedTextAttributes  = [
            .backgroundColor: NSColor.white.withAlphaComponent(0.15)
        ]
        tv.textContainerInset      = NSSize(width: 96, height: 56)
        tv.isVerticallyResizable   = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask        = [.width]
        tv.maxSize                 = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                            height: CGFloat.greatestFiniteMagnitude)
        tv.delegate                = context.coordinator

        tv.navigateToNote = { [weak s = context.coordinator.store] title in
            DispatchQueue.main.async {
                guard let s = s else { return }
                if let target = s.allNotes.first(where: {
                    $0.title.lowercased() == title.lowercased() }) {
                    s.selectedNote = target
                } else {
                    s.createNote(title: title)
                }
            }
        }
        tv.getNoteTitles = { [weak s = context.coordinator.store] in
            s?.noteTitles() ?? []
        }

        tv.string   = note.resolvedContent()   // lazy-load from disk
        scroll.documentView = tv
        bridge.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? WikilinkTextView else { return }
        context.coordinator.note  = note
        context.coordinator.store = store

        if !context.coordinator.isDirty {
            let fresh = note.resolvedContent()
            if tv.string != fresh {
                let sel = tv.selectedRange()
                tv.string = fresh
                let safe  = NSRange(location: min(sel.location, tv.string.utf16.count), length: 0)
                tv.setSelectedRange(safe)
            }
        }
    }

    // MARK: – Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var store:   NoteStore
        var note:    Note
        var isDirty  = false
        private var saveTimer: Timer?

        init(store: NoteStore, note: Note) {
            self.store = store; self.note = note
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? WikilinkTextView else { return }
            // Cursor movement without text change — sync location for checkbox re-render
            (tv.textStorage as? WikilinkTextStorage)?.cursorLocation = tv.selectedRange().location
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? WikilinkTextView else { return }
            isDirty = true
            let content = tv.string

            tv.handleTextChange()

            // Headline rename
            if let firstLine = content.components(separatedBy: "\n").first,
               firstLine.hasPrefix("# ") {
                let newTitle = String(firstLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !newTitle.isEmpty && newTitle != note.title {
                    note.title = newTitle
                    store.renameNote(note, newTitle: newTitle)
                }
            }

            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.store.saveNote(self.note, content: content)
                self.isDirty = false
            }
        }
    }
}

// MARK: – Empty state

struct EmptyEditorView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("select a note")
                .font(F.syneUI(13))
                .foregroundColor(C.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(C.bg)
    }
}
