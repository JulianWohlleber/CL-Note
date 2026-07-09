import SwiftUI
import AppKit

@main
struct Note_App: App {
    @StateObject private var store = NoteStore()
    @AppStorage("note_.didCompleteSetup") private var didCompleteSetup = false
    @State private var showSetup = false

    init() {
        registerFonts()
        Self.migrateSetupFlag()
    }

    /// One-time copy of the pre-rename UserDefaults key so returning users
    /// aren't asked to redo setup. NOTE: the literal "merken.didCompleteSetup"
    /// is intentional; do not rename.
    private static func migrateSetupFlag() {
        let d = UserDefaults.standard
        guard d.object(forKey: "note_.didCompleteSetup") == nil,
              let legacy = d.object(forKey: "merken.didCompleteSetup") as? Bool else { return }
        d.set(legacy, forKey: "note_.didCompleteSetup")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .sheet(isPresented: $showSetup) {
                    SetupWizardView(isPresented: $showSetup,
                                    didCompleteSetup: $didCompleteSetup)
                        .environmentObject(store)
                }
                .onAppear {
                    // Source of truth: the vault must actually exist on disk.
                    // The completion flag alone can lie (external drive
                    // unmounted, vault folder deleted, migration failed).
                    showSetup = (store.vaultURL == nil)
                    if store.vaultURL != nil { didCompleteSetup = true }
                    configureWindow()
                }
                .onChange(of: store.vaultURL) { newValue in
                    // If the user removes their last vault mid-session, bring
                    // the wizard back instead of leaving them stranded.
                    if newValue == nil { showSetup = true }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.createNote() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Chat") {
                    store.requestedTab = AppTab.chat.rawValue
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Notes") {
                    store.requestedTab = AppTab.notes.rawValue
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Tasks") {
                    store.toggleTasksRequest += 1
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()
                Button("Open Vault…") { store.pickVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Reload Notes") { store.loadNotes() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Summarize Vault Now") {
                    Task { await SummaryEngine.shared.run(store: store) }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }

    private func configureWindow() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        guard let win = NSApp.windows.first else { return }
        win.titlebarAppearsTransparent = true
        win.titleVisibility            = .hidden
        win.backgroundColor            = C.bgNS
        win.isMovableByWindowBackground = true
        win.setContentSize(NSSize(width: 1100, height: 700))
        win.minSize = NSSize(width: 760, height: 500)
    }
}
