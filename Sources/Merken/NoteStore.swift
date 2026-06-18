import Foundation
import AppKit
import Combine

// MARK: – Task model

struct NoteTask: Identifiable {
    /// Stable ID based on file + line so it survives rebuildTasks().
    var id: String { "\(sourceFile):\(lineIndex)" }
    var text: String
    var done: Bool
    var sourceFile: String   // lastPathComponent of the note file
    var lineIndex: Int       // line number in file
}

// MARK: – Store

class NoteStore: ObservableObject {
    @Published var notes:        [Note]      = []
    @Published var summaries:    [Note]      = []
    @Published var tasks:        [NoteTask]  = []
    @Published var selectedNote: Note?
    @Published var vaultURL:     URL?

    /// Tab requested from elsewhere in the app (e.g. chat source click → notes).
    @Published var requestedTab: String?

    /// Incremented each time Tasks panel should toggle (⌘T).
    @Published var toggleTasksRequest: Int = 0

    // Multi-vault
    @Published var vaultEntries: [VaultEntry] = []
    @Published var activeVaultID: String       = ""

    // Persistent AI index — rebuilt incrementally in the background.
    @Published var vaultIndex: VaultIndex = VaultIndex.empty(vaultPath: "")
    @Published var indexProgress: String = ""
    private var indexingTask: Task<Void, Never>?

    var activeVaultName: String {
        vaultEntries.first { $0.id == activeVaultID }?.name ?? "Merken"
    }

    private let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Merken")
    }()
    private var configURL: URL { supportDir.appendingPathComponent("config.json") }
    private var vaultsURL: URL { supportDir.appendingPathComponent("vaults.json") }

    private static let skipDirs: Set<String> = [
        ".venv", "vault-chat", "node_modules", ".git", ".claude", ".obsidian", ".trash"
    ]
    static let summariesDir = "summaries"

    init() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        loadConfig()
    }

    // MARK: – Config

    private func loadConfig() {
        // Try Merken vaults.json
        if let data = try? Data(contentsOf: vaultsURL),
           let cfg  = try? JSONDecoder().decode(VaultsConfig.self, from: data) {
            vaultEntries  = cfg.vaults
            activeVaultID = cfg.active
            if let v = cfg.vaults.first(where: { $0.id == cfg.active }),
               FileManager.default.fileExists(atPath: v.path) {
                vaultURL = URL(fileURLWithPath: v.path)
                loadNotes(); return
            }
        }
        // Migrate from design_space
        let dsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/design_space/vaults.json")
        if let data   = try? Data(contentsOf: dsPath),
           let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let active = json["active"] as? String,
           let vaults = json["vaults"] as? [[String: Any]] {
            let entries = vaults.compactMap { v -> VaultEntry? in
                guard let id   = v["id"]   as? String,
                      let name = v["name"] as? String,
                      let path = v["path"] as? String else { return nil }
                return VaultEntry(id: id, name: name, path: path)
            }
            vaultEntries  = entries
            activeVaultID = active
            saveConfig()
            if let e = entries.first(where: { $0.id == active }),
               FileManager.default.fileExists(atPath: e.path) {
                vaultURL = URL(fileURLWithPath: e.path)
                loadNotes()
            }
        }
    }

    private func saveConfig() {
        let cfg = VaultsConfig(active: activeVaultID, vaults: vaultEntries)
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: vaultsURL)
        }
    }

    // MARK: – Vault management

    func addVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose vault folder"; panel.canChooseFiles = false
        panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Select Vault"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.lastPathComponent.replacingOccurrences(of: "-", with: " ")
        let id   = UUID().uuidString.prefix(8).lowercased()
        let entry = VaultEntry(id: String(id), name: name, path: url.path)
        vaultEntries.append(entry)
        saveConfig()
        switchVault(entry)
    }

    func pickVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose vault folder"; panel.canChooseFiles = false
        panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Select Vault"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name  = url.lastPathComponent.replacingOccurrences(of: "-", with: " ")
        let id    = UUID().uuidString.prefix(8).lowercased()
        let entry = VaultEntry(id: String(id), name: name, path: url.path)
        if !vaultEntries.contains(where: { $0.path == url.path }) {
            vaultEntries.append(entry)
        }
        switchVault(entry)
    }

    func switchVault(_ entry: VaultEntry) {
        guard FileManager.default.fileExists(atPath: entry.path) else { return }
        activeVaultID = entry.id
        vaultURL      = URL(fileURLWithPath: entry.path)
        selectedNote  = nil
        notes         = []; summaries = []; tasks = []
        saveConfig()
        loadNotes()
    }

    // MARK: – Load

    func loadNotes() {
        guard let vaultURL = vaultURL else { return }
        let skipDirs = Self.skipDirs
        let summDir  = Self.summariesDir
        let vaultID  = activeVaultID

        // Cancel any in-flight indexing from a previous vault.
        indexingTask?.cancel()

        // ── Phase 1 — enumerate files with metadata only (FAST) ────────────
        // The sidebar populates immediately; no file *content* is read here.
        Task.detached(priority: .userInitiated) {
            var rootNotes:  [Note] = []
            var summaries:  [Note] = []

            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: vaultURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for case let fileURL as URL in enumerator {
                if fileURL.pathComponents.contains(where: { skipDirs.contains($0) }) {
                    enumerator.skipDescendants(); continue
                }
                guard fileURL.pathExtension == "md" else { continue }

                let rel       = String(fileURL.path.dropFirst(vaultURL.path.count + 1))
                let isSummary = rel.hasPrefix(summDir + "/")
                let note      = Note(fileURL: fileURL, isSummary: isSummary)

                if isSummary { summaries.append(note) } else { rootNotes.append(note) }
            }
            rootNotes.sort { $0.modifiedDate > $1.modifiedDate }
            summaries.sort { $0.modifiedDate > $1.modifiedDate }

            let notesSnapshot = rootNotes

            // Publish the list immediately so the sidebar shows up.
            await MainActor.run {
                self.notes     = rootNotes
                self.summaries = summaries
                self.tasks     = []   // will stream in during phase 2
            }

            // ── Phase 2 — incremental task extraction (BACKGROUND) ─────────
            // Reads each note's content transiently, then discards it. Publishes
            // tasks in batches so a sluggish disk doesn't stall the whole pass.
            await self.extractTasksIncrementally(for: notesSnapshot)

            // ── Phase 3 — AI search index (BACKGROUND, incremental) ────────
            await self.buildOrUpdateIndex(for: notesSnapshot, vaultID: vaultID)
        }
    }

    // MARK: – Phase 2: incremental task extraction

    private func extractTasksIncrementally(for notes: [Note]) async {
        var pending: [NoteTask] = []
        let batchSize = 50
        let maxScanBytes = 2 * 1024 * 1024   // 2 MB — tasks don't live in huge blobs

        for (i, note) in notes.enumerated() {
            if Task.isCancelled { return }
            let size = (try? note.fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size <= maxScanBytes,
               let text = try? String(contentsOf: note.fileURL, encoding: .utf8) {
                pending.append(contentsOf: Self.extractTasksFromText(
                    text, sourceFile: note.fileURL.lastPathComponent))
            }
            // Flush every N files so the UI stays live and memory stays flat.
            if (i + 1) % batchSize == 0 {
                let batch = pending; pending.removeAll(keepingCapacity: true)
                await MainActor.run { self.tasks.append(contentsOf: batch) }
            }
        }
        if !pending.isEmpty {
            let final = pending
            await MainActor.run { self.tasks.append(contentsOf: final) }
        }
    }

    // MARK: – Phase 3: AI search index

    /// Runs on a detached task. Loads the saved index, then walks notes and
    /// refreshes entries whose mtime/size changed. Saves incrementally.
    private func buildOrUpdateIndex(for notes: [Note], vaultID: String) async {
        guard !vaultID.isEmpty else { return }

        let vaultPath = await MainActor.run { self.vaultURL?.path ?? "" }

        // Start from a saved index if we have one; keeps launch snappy.
        var idx = VaultIndex.load(fromVaultID: vaultID) ?? VaultIndex.empty(vaultPath: vaultPath)
        idx.vaultPath = vaultPath   // refresh in case the vault was moved on disk
        await MainActor.run { self.vaultIndex = idx }

        let fm = FileManager.default
        let total = notes.count
        var updated = 0
        var touched = false
        let saveEvery = 80   // persist every N changes so crashes don't lose work

        for (i, note) in notes.enumerated() {
            if Task.isCancelled { return }

            // Read size + mtime cheaply via resourceValues.
            let vals = try? note.fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = vals?.contentModificationDate ?? note.modifiedDate
            let size  = vals?.fileSize ?? 0

            let key = note.fileURL.lastPathComponent
            if let existing = idx.entries[key],
               existing.modified == mtime,
               existing.size == size {
                continue   // unchanged — skip expensive read
            }

            if let entry = VaultIndex.makeEntry(fileURL: note.fileURL,
                                                modified: mtime,
                                                size: size) {
                idx.entries[key] = entry
                touched  = true
                updated += 1
            }

            if updated > 0 && updated % saveEvery == 0 {
                let snapshot = idx
                idx.save(vaultID: vaultID)
                await MainActor.run {
                    self.vaultIndex    = snapshot
                    self.indexProgress = "Indexing \(min(i + 1, total))/\(total)…"
                }
                // Yield briefly so the main thread stays responsive.
                try? await Task.sleep(nanoseconds: 10_000_000)
            }

            // Skip orphaned entries for files that no longer exist. We'll do a
            // full prune pass at the end so we don't query FS twice per entry.
            _ = fm
        }

        // Prune entries for files that are no longer present.
        let presentKeys = Set(notes.map { $0.fileURL.lastPathComponent })
        idx.entries = idx.entries.filter { presentKeys.contains($0.key) }

        if touched {
            idx.save(vaultID: vaultID)
        }
        let finalIdx = idx
        await MainActor.run {
            self.vaultIndex    = finalIdx
            self.indexProgress = touched ? "Index up to date (\(updated) updated)" : ""
        }
    }

    /// Extract tasks from raw markdown text — doesn't require a loaded Note.
    static func extractTasksFromText(_ text: String, sourceFile: String) -> [NoteTask] {
        var result: [NoteTask] = []
        let lines = text.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [ ] ") {
                result.append(NoteTask(text: String(t.dropFirst(6)), done: false,
                                       sourceFile: sourceFile, lineIndex: idx))
            } else if t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") {
                result.append(NoteTask(text: String(t.dropFirst(6)), done: true,
                                       sourceFile: sourceFile, lineIndex: idx))
            }
        }
        return result
    }

    /// Reads a note from disk and extracts tasks. Discards content after.
    private func extractTasks(from note: Note) -> [NoteTask] {
        let text = note.readContent()
        return Self.extractTasksFromText(text, sourceFile: note.fileURL.lastPathComponent)
    }

    func toggleTask(_ task: NoteTask) {
        guard let noteIdx = notes.firstIndex(where: { $0.fileURL.lastPathComponent == task.sourceFile })
        else { return }

        // Always re-read from disk so we operate on the freshest content.
        let fileURL    = notes[noteIdx].fileURL
        guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        var lines = content.components(separatedBy: "\n")

        // Find the target line: try the stored index first, then scan for text match.
        func markerLine(for task: NoteTask, in lines: [String]) -> Int? {
            // Fast path: stored index still has our text
            if task.lineIndex < lines.count {
                let candidate = lines[task.lineIndex]
                if candidate.contains(task.text) &&
                   (candidate.contains("- [ ] ") || candidate.contains("- [x] ") || candidate.contains("- [X] ")) {
                    return task.lineIndex
                }
            }
            // Fallback: scan for matching task text
            for (i, line) in lines.enumerated() {
                if line.contains(task.text) &&
                   (line.contains("- [ ] ") || line.contains("- [x] ") || line.contains("- [X] ")) {
                    return i
                }
            }
            return nil
        }

        guard let lineIdx = markerLine(for: task, in: lines) else { return }

        let line    = lines[lineIdx]
        let nowDone: Bool
        if line.contains("- [ ] ") {
            lines[lineIdx] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
            nowDone = true
        } else {
            lines[lineIdx] = line
                .replacingOccurrences(of: "- [x] ", with: "- [ ] ")
                .replacingOccurrences(of: "- [X] ", with: "- [ ] ")
            nowDone = false
        }

        content = lines.joined(separator: "\n")
        // Write to disk (no in-memory cache — stays lazy to keep RAM flat).
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        notes[noteIdx].modifiedDate = Date()
        // Update in-memory task (stable ID survives this assignment)
        if let taskIdx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[taskIdx].done = nowDone
        }
    }

    func jumpToTaskNote(_ task: NoteTask) {
        guard let note = notes.first(where: { $0.fileURL.lastPathComponent == task.sourceFile })
        else { return }
        selectedNote  = note
        requestedTab  = AppTab.notes.rawValue   // switch to Notes tab
    }

    /// Append a new task to the vault's `Tasks.md` file (creates it if missing).
    /// Mirrors design_space's `/api/todo` endpoint.
    @discardableResult
    func addTask(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let vaultURL = vaultURL else { return false }

        let tasksURL = vaultURL.appendingPathComponent("Tasks.md")
        var content  = (try? String(contentsOf: tasksURL, encoding: .utf8)) ?? ""
        if content.isEmpty {
            content = "# Tasks\n\n- [ ] \(trimmed)\n"
        } else {
            if !content.hasSuffix("\n") { content += "\n" }
            content += "- [ ] \(trimmed)\n"
        }

        do {
            try content.write(to: tasksURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }

        // Reflect in memory — we do NOT cache content; lazy-load on demand.
        if let idx = notes.firstIndex(where: { $0.fileURL == tasksURL }) {
            notes[idx].modifiedDate = Date()
        } else {
            let note = Note(fileURL: tasksURL)
            notes.insert(note, at: 0)
        }
        // Only the Tasks.md file changed — rescan just that file's tasks and
        // merge rather than re-reading every note in the vault.
        let newFileTasks = Self.extractTasksFromText(content,
                                                    sourceFile: tasksURL.lastPathComponent)
        var merged = tasks.filter { $0.sourceFile != tasksURL.lastPathComponent }
        merged.append(contentsOf: newFileTasks)
        merged.sort { t1, t2 in
            let d1 = notes.first { $0.fileURL.lastPathComponent == t1.sourceFile }?.modifiedDate ?? .distantPast
            let d2 = notes.first { $0.fileURL.lastPathComponent == t2.sourceFile }?.modifiedDate ?? .distantPast
            if d1 != d2 { return d1 > d2 }
            return t1.lineIndex > t2.lineIndex
        }
        tasks = merged
        return true
    }

    // MARK: – CRUD

    func createNote(title: String? = nil) {
        guard let vaultURL = vaultURL else { pickVault(); return }
        var base = title ?? "Untitled"; var counter = 1
        var fileURL = vaultURL.appendingPathComponent("\(base).md")
        while FileManager.default.fileExists(atPath: fileURL.path) {
            base = (title ?? "Untitled") + " \(counter)"; counter += 1
            fileURL = vaultURL.appendingPathComponent("\(base).md")
        }
        let content = "# \(base)\n\n"
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        let note = Note(fileURL: fileURL)
        DispatchQueue.main.async {
            self.notes.insert(note, at: 0)
            self.selectedNote = self.notes[0]
        }
    }

    func deleteNote(_ note: Note) {
        try? FileManager.default.trashItem(at: note.fileURL, resultingItemURL: nil)
        DispatchQueue.main.async {
            self.notes.removeAll { $0.id == note.id }
            self.summaries.removeAll { $0.id == note.id }
            if self.selectedNote?.id == note.id { self.selectedNote = self.notes.first }
        }
    }

    func saveNote(_ note: Note, content: String) {
        try? content.write(to: note.fileURL, atomically: true, encoding: .utf8)
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx].modifiedDate = Date()   // no content cache — stays lazy
        }
    }

    func renameNote(_ note: Note, newTitle: String) {
        let san = newTitle.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-")
        guard !san.isEmpty else { return }
        let newURL = note.fileURL.deletingLastPathComponent().appendingPathComponent("\(san).md")
        guard newURL != note.fileURL, !FileManager.default.fileExists(atPath: newURL.path) else { return }
        try? FileManager.default.moveItem(at: note.fileURL, to: newURL)
        DispatchQueue.main.async {
            if let idx = self.notes.firstIndex(where: { $0.id == note.id }) {
                self.notes[idx].fileURL = newURL; self.notes[idx].title = san
            }
            if self.selectedNote?.id == note.id {
                self.selectedNote?.fileURL = newURL; self.selectedNote?.title = san
            }
        }
    }

    var allNotes: [Note] { notes + summaries }
    func noteTitles() -> [String] { notes.map(\.title) }
}
