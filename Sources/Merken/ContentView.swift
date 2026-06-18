import SwiftUI

enum AppTab: String, CaseIterable { case chat = "Chat", notes = "Notes" }

// Fixed row heights so sidebar and main content dividers land on the same pixel.
private let kVaultRowH:   CGFloat = 44
private let kToolbarRowH: CGFloat = 38

struct ContentView: View {
    @EnvironmentObject var store: NoteStore
    @StateObject private var bridge = EditorBridge()

    @State private var tab:            AppTab  = .chat
    @State private var sidebarWidth:   CGFloat = 240
    @State private var tasksPanelOpen: Bool    = false
    @State private var tasksWidth:     CGFloat = 300

    var body: some View {
        HStack(spacing: 0) {

            // ── Left sidebar ─────────────────────────────────────────────
            VStack(spacing: 0) {
                // Row 1: vault switcher — fixed height matches main Row 1
                VaultSwitcherButton()
                    .padding(.horizontal, 14)
                    .frame(height: kVaultRowH)

                Rectangle().fill(C.border).frame(height: 1)

                // Row 2: tabs — fixed height matches toolbar row
                SidebarTabs(tab: $tab)
                    .frame(height: kToolbarRowH)

                Rectangle().fill(C.border).frame(height: 1)

                // Body
                Group {
                    if tab == .chat { ChatSidebarList() }
                    else            { SidebarView(tab: tab) }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: sidebarWidth)
            .background(C.bgSide)
            // Drag-resize handle
            .overlay(alignment: .trailing) {
                Color.clear.frame(width: 4)
                    .contentShape(Rectangle())
                    .onHover { NSCursor.resizeLeftRight.set(); if !$0 { NSCursor.arrow.set() } }
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { sidebarWidth = max(180, min(420, sidebarWidth + $0.translation.width)) })
            }

            Rectangle().fill(C.border).frame(width: 1)

            // ── Main content ─────────────────────────────────────────────
            VStack(spacing: 0) {
                // Row 1: Tasks toggle — same fixed height as vault row
                HStack {
                    Spacer()
                    if !tasksPanelOpen {
                        TopBarTasksButton(open: $tasksPanelOpen,
                                          count: store.tasks.filter { !$0.done }.count)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: kVaultRowH)

                Rectangle().fill(C.border).frame(height: 1)

                // Row 2: toolbar (Notes) or empty band (Chat) — same fixed height as tabs
                if tab == .notes {
                    EditorToolbar(bridge: bridge)
                        .frame(height: kToolbarRowH)
                } else {
                    Color.clear.frame(height: kToolbarRowH)
                }

                Rectangle().fill(C.border).frame(height: 1)

                // Main view
                Group {
                    switch tab {
                    case .chat:
                        ChatView()
                    case .notes:
                        if let note = store.selectedNote {
                            EditorView(note: note, bridge: bridge).id(note.id)
                        } else {
                            EmptyEditorView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
            .background(C.bg)
            // Model switcher — bottom-right overlay
            .overlay(alignment: .bottomTrailing) {
                ModelSwitcher()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }

            // ── Tasks panel ───────────────────────────────────────────────
            if tasksPanelOpen {
                Rectangle().fill(C.border).frame(width: 1)

                VStack(spacing: 0) {
                    // Row 1: header — same height as vault row
                    HStack {
                        Text("Tasks")
                            .font(F.syneUI(12, weight: .bold))
                            .foregroundColor(C.text)
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { tasksPanelOpen = false }
                        } label: {
                            Icon.close.view(size: 11)
                        }
                        .buttonStyle(.plain)
                        .help("Close  ⌘T")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: kVaultRowH)

                    Rectangle().fill(C.border).frame(height: 1)

                    // Row 2: empty band — same height as toolbar row
                    Color.clear.frame(height: kToolbarRowH)

                    Rectangle().fill(C.border).frame(height: 1)

                    // Tasks body
                    TasksBodyOnly()
                }
                .frame(width: tasksWidth)
                .background(C.bgSide)
                .transition(.move(edge: .trailing))
                // Drag-resize on leading edge
                .overlay(alignment: .leading) {
                    Color.clear.frame(width: 4)
                        .contentShape(Rectangle())
                        .onHover { NSCursor.resizeLeftRight.set(); if !$0 { NSCursor.arrow.set() } }
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { tasksWidth = max(240, min(520, tasksWidth - $0.translation.width)) })
                }
            }
        }
        .background(C.bg)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(store.$requestedTab.compactMap { $0 }) { raw in
            if let t = AppTab(rawValue: raw) { tab = t }
            store.requestedTab = nil
        }
        .onReceive(store.$toggleTasksRequest.dropFirst()) { _ in
            withAnimation(.easeOut(duration: 0.18)) { tasksPanelOpen.toggle() }
        }
    }
}

// MARK: – Centered tab labels

struct SidebarTabs: View {
    @Binding var tab: AppTab
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            TabLabel(title: "Chat",  shortcut: "⌘1", active: tab == .chat)  { tab = .chat  }
            Spacer()
            TabLabel(title: "Notes", shortcut: "⌘2", active: tab == .notes) { tab = .notes }
            Spacer()
        }
    }
}

private struct TabLabel: View {
    let title: String; let shortcut: String; let active: Bool; let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(F.syneUI(12, weight: active ? .bold : .regular))
                        .foregroundColor(active ? C.text : (hovered ? C.text : C.textDim))
                    if !active {
                        Text(shortcut).font(F.syneUI(9)).foregroundColor(C.textFaint)
                    }
                }
                if active { C.primary.frame(height: 1.5) }
                else      { Color.clear.frame(height: 1.5) }
            }
            .fixedSize().contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
    }
}

// MARK: – Top-bar Tasks button

struct TopBarTasksButton: View {
    @Binding var open: Bool
    let count: Int
    @State private var hovered = false
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { open.toggle() } } label: {
            HStack(spacing: 6) {
                Text("Tasks").font(F.syneUI(11))
                    .foregroundColor(hovered ? C.text : C.textDim)
                Text("⌘T").font(F.syneUI(9)).foregroundColor(C.textFaint)
                if count > 0 { Text("\(count)").font(F.syneUI(9)).foregroundColor(C.textFaint) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? C.bgHover : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }.help("Show Tasks  ⌘T")
    }
}
