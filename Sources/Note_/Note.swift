import Foundation

struct Note: Identifiable, Hashable {
    let id: UUID
    var title: String
    /// In-memory cached content. Empty by default — use `readContent()` to get
    /// a fresh copy from disk. Only the actively edited note caches content
    /// via `saveNote` to avoid re-reads on every keystroke.
    var content: String
    var fileURL: URL
    var isSummary: Bool
    var modifiedDate: Date

    init(fileURL: URL, isSummary: Bool = false) {
        self.id          = UUID()
        self.fileURL     = fileURL
        self.isSummary   = isSummary
        self.title       = fileURL.deletingPathExtension().lastPathComponent
        self.content     = ""   // lazy — not read from disk on init
        let vals         = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        self.modifiedDate = vals?.contentModificationDate ?? Date.distantPast
    }

    /// Read the note's markdown from disk. Does NOT mutate the cached `content`.
    /// Call sites use this for transient operations (chat ranking, summaries,
    /// task scans) so the text is released after use instead of sitting in RAM.
    func readContent() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Return the cached content if non-empty, otherwise read from disk.
    func resolvedContent() -> String {
        content.isEmpty ? readContent() : content
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Note, rhs: Note) -> Bool { lhs.id == rhs.id }
}
