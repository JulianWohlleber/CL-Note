import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: NoteStore
    @ObservedObject var summaryEngine = SummaryEngine.shared
    let tab: AppTab
    @State private var search = ""

    /// All non-summary notes in the vault (any depth).
    private var filteredNotes: [Note] {
        guard !search.isEmpty else { return store.notes }
        return store.notes.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var filteredSummaries: [Note] {
        guard !search.isEmpty else { return store.summaries }
        return store.summaries.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Search + New ──────────────────────────────────────────────
            HStack(spacing: 8) {
                Icon.search.view(size: 12)
                TextField("Filter…", text: $search)
                    .font(F.syneUI(12))
                    .foregroundColor(C.text)
                    .textFieldStyle(.plain)
                Spacer()
                Button { store.createNote() } label: {
                    Icon.plus.view(size: 12)
                }
                .buttonStyle(.plain)
                .help("New Note  ⌘N")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // ── Note list ─────────────────────────────────────────────────
            ScrollView {
                LazyVStack(spacing: 0) {

                    // Root-level notes only
                    ForEach(filteredNotes) { note in
                        NoteRowView(note: note,
                                    isSelected: store.selectedNote?.id == note.id)
                            .onTapGesture { store.selectedNote = note }
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.deleteNote(note) }
                            }
                    }

                    // ── Summaries section ─────────────────────────────────
                    HStack(spacing: 6) {
                        Text("SUMMARIES")
                            .font(F.syneUI(9))
                            .foregroundColor(C.textFaint)
                            .tracking(1.2)
                        Spacer()
                        if summaryEngine.isRunning {
                            ProgressView()
                                .scaleEffect(0.45)
                                .frame(width: 12, height: 12)
                        } else {
                            Button {
                                Task { await summaryEngine.run(store: store) }
                            } label: {
                                Icon.sparkles.view(size: 12, color: C.textFaint)
                            }
                            .buttonStyle(.plain)
                            .help("Regenerate summaries")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 20)
                    .padding(.bottom, 4)

                    if filteredSummaries.isEmpty {
                        Text(summaryEngine.isRunning ? summaryEngine.progress : "No summaries yet")
                            .font(F.syneUI(10))
                            .foregroundColor(C.textFaint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(filteredSummaries) { note in
                            NoteRowView(note: note,
                                        isSelected: store.selectedNote?.id == note.id)
                                .onTapGesture { store.selectedNote = note }
                        }
                    }
                }
            }
        }
        .background(C.bgSide)
    }
}

// MARK: – Note row

struct NoteRowView: View {
    let note: Note
    let isSelected: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isSelected ? C.primaryStart : Color.clear)
                .frame(width: 2)

            Text(note.title)
                .font(F.syneUI(12))
                .foregroundColor(isSelected ? C.text : (hovered ? C.accent : C.textDim))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Spacer()
        }
        .background(isSelected ? C.bgHover : (hovered ? C.bgHover.opacity(0.5) : Color.clear))
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }
}
