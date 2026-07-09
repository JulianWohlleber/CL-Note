import SwiftUI

// MARK: – Chat message model (in-memory)

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id:      UUID
    let role:    Role
    let text:    String
    let sources: [ChatSource]

    init(id: UUID = UUID(), role: Role, text: String, sources: [ChatSource]) {
        self.id      = id
        self.role    = role
        self.text    = text
        self.sources = sources
    }
}

// MARK: – Main chat view

struct ChatView: View {
    @EnvironmentObject var store:     NoteStore
    @StateObject private var chatStore = ChatStore.shared
    @State private var input     = ""
    @State private var isLoading = false
    @State private var ollamaOK  = true
    @State private var renamingSession: ChatSession? = nil
    @State private var renameText = ""

    private var messages: [ChatMessage] {
        (chatStore.activeSession?.messages ?? []).map(\.asChatMessage)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Messages ─────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if messages.isEmpty {
                            welcome.padding(.top, 80)
                        }
                        ForEach(messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                        if isLoading {
                            LoadingDots()
                                .padding(.leading, 4)
                                .id("loading")
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        if let lastID = messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        } else {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }

            // ── Ollama status ─────────────────────────────────────────────
            if !ollamaOK {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 6, height: 6)
                    Text("Ollama not running — start it to enable chat")
                        .font(F.syneUI(11))
                        .foregroundColor(C.textDim)
                    Spacer()
                    Button("Check again") { Task { await checkOllama() } }
                        .font(F.syneUI(11))
                        .buttonStyle(.plain)
                        .foregroundColor(C.textDim)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.05))
            }

            Divider().background(C.border)

            // ── Input row ────────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask anything…", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(F.syneUI(13))
                    .foregroundColor(C.text)
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(C.border, lineWidth: 1)
                    )
                    .onSubmit { send() }

                Button { send() } label: {
                    Icon.arrow.view(size: 14, color: input.isEmpty || isLoading ? C.textFaint : C.textDim)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(C.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(input.isEmpty || isLoading)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(C.bg)
        .task { await checkOllama() }
    }

    // MARK: – Welcome

    private var welcome: some View {
        VStack(spacing: 8) {
            Text("Ask your vault")
                .font(F.syneUI(15, weight: .bold))
                .foregroundColor(C.text)
            Text("Answers are grounded in your notes and summaries.")
                .font(F.syneUI(12))
                .foregroundColor(C.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: – Actions

    private func send() {
        guard let sessionID = chatStore.activeSession?.id else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMsg = ChatMessage(role: .user, text: text, sources: [])
        chatStore.append(message: userMsg.persisted, to: sessionID)
        input     = ""
        isLoading = true

        let index = store.vaultIndex

        Task {
            let result  = await OllamaClient.shared.chat(query: text, index: index)
            let botMsg  = ChatMessage(role: .assistant, text: result.answer, sources: result.sources)
            await MainActor.run {
                chatStore.append(message: botMsg.persisted, to: sessionID)
                isLoading = false
            }
        }
    }

    private func checkOllama() async {
        ollamaOK = await OllamaClient.shared.isRunning()
    }
}

// MARK: – Message row (design_space style)

struct MessageRow: View {
    @EnvironmentObject var store: NoteStore
    let message: ChatMessage
    var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isUser {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(C.textDim)
                        .frame(width: 2)
                    Text(message.text)
                        .font(F.syneUI(13).italic())
                        .foregroundColor(C.textDim)
                        .lineSpacing(5)
                        .padding(.leading, 14)
                        .textSelection(.enabled)
                }
            } else {
                Text(message.text)
                    .font(F.syneUI(13.5))
                    .foregroundColor(C.text)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !message.sources.isEmpty {
                    sourcesBlock
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourcesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOURCES")
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(C.textFaint)

            FlowLayout(spacing: 6) {
                ForEach(message.sources) { src in
                    SourceChip(source: src)
                }
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(C.border).frame(height: 1)
        }
    }
}

// MARK: – Source chip

struct SourceChip: View {
    @EnvironmentObject var store: NoteStore
    let source: ChatSource
    @State private var hovered     = false
    @State private var showPopover = false

    private var note: Note? {
        store.allNotes.first { $0.fileURL.lastPathComponent == source.file }
    }

    var body: some View {
        Text(source.title)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(hovered ? C.text : C.textDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(hovered ? C.textDim : C.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                hovered = inside
                if inside {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if hovered { showPopover = true }
                    }
                } else {
                    showPopover = false
                }
            }
            .onTapGesture {
                guard let note = note else { return }
                store.selectedNote = note
                store.requestedTab = AppTab.notes.rawValue
            }
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                NotePreview(note: note, title: source.title)
            }
            .help("Click to open · Hover to preview")
    }
}

private struct NotePreview: View {
    let note: Note?
    let title: String

    private var preview: String {
        guard let c = note?.resolvedContent() else { return "" }
        let lines = c.components(separatedBy: "\n")
        let body  = lines.first?.hasPrefix("# ") == true
            ? lines.dropFirst().joined(separator: "\n")
            : c
        return String(body.prefix(800))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note?.title ?? title)
                .font(F.syneUI(13, weight: .bold))
                .foregroundColor(C.text)
            Divider().background(C.border)
            ScrollView {
                Text(preview.isEmpty ? "Note is empty." : preview)
                    .font(F.syneUI(12))
                    .foregroundColor(C.textDim)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
        }
        .padding(14)
        .frame(width: 360)
        .background(C.bg)
    }
}

// MARK: – Sidebar chat list (used by LeftSidebar)

struct ChatSidebarList: View {
    @ObservedObject var chatStore = ChatStore.shared
    @State private var renamingID: UUID?   = nil
    @State private var renameText: String  = ""

    var body: some View {
        VStack(spacing: 0) {
            // New chat button
            Button { chatStore.newSession() } label: {
                HStack(spacing: 8) {
                    Icon.plus.view(size: 11)
                    Text("New chat")
                        .font(F.syneUI(12))
                        .foregroundColor(C.textDim)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().background(C.border)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(chatStore.sessions) { session in
                        ChatSessionRow(
                            session:     session,
                            isActive:    chatStore.activeSession?.id == session.id,
                            renamingID:  $renamingID,
                            renameText:  $renameText,
                            onSelect:    { chatStore.select(session) },
                            onDelete:    { chatStore.delete(session) },
                            onRename:    { chatStore.rename(session, to: renameText) }
                        )
                    }
                }
            }
        }
    }
}

private struct ChatSessionRow: View {
    let session:    ChatSession
    let isActive:   Bool
    @Binding var renamingID: UUID?
    @Binding var renameText: String
    let onSelect:   () -> Void
    let onDelete:   () -> Void
    let onRename:   () -> Void
    @State private var hovered = false

    var isRenaming: Bool { renamingID == session.id }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isActive ? C.primaryStart : Color.clear)
                .frame(width: 2)

            Group {
                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(F.syneUI(12))
                        .foregroundColor(C.text)
                        .onSubmit { commitRename() }
                } else {
                    Text(session.title)
                        .font(F.syneUI(12))
                        .foregroundColor(isActive ? C.text : (hovered ? C.text : C.textDim))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Spacer()
        }
        .background(isActive ? C.bgHover : (hovered ? C.bgHover.opacity(0.5) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename") {
                renameText  = session.title
                renamingID  = session.id
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .animation(.easeInOut(duration: 0.1), value: hovered)
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }

    private func commitRename() {
        let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { onRename() }
        renamingID = nil
    }
}

// MARK: – Loading dots

struct LoadingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(C.textDim)
                    .frame(width: 4, height: 4)
                    .opacity(phase == i ? 1 : 0.25)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.28, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: – Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
