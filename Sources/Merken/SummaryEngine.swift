import Foundation
import CryptoKit

/// Generates summaries for "parent" notes (notes that link to other notes via [[wikilinks]]).
/// Mirrors design_space's `summarize_vault()`.
///
/// · Walks all notes, finds those containing [[wikilinks]] — those are parents.
/// · Timestamped notes (`YYYY-MM-DD`, `YYMMDD`, etc.) are never parents.
/// · For each parent, sends parent + child excerpts to Ollama to get a structured summary.
/// · Writes `summaries/[Stem] Summary.md` with frontmatter metadata for incremental re-runs.
/// · Cleans up orphaned summary files.
@MainActor
final class SummaryEngine: ObservableObject {
    static let shared = SummaryEngine()

    @Published var isRunning      = false
    @Published var progress       = ""
    @Published var lastGenerated  = 0

    private static let summariesDir = "summaries"
    private static let timestampRE  = #"^(\d{4}-\d{2}-\d{2}|\d{2}-\d{2}-\d{2}|\d{6})"#
    private static let wikilinkRE   = #"\[\[([^\]\|]+?)(?:\|[^\]]+)?\]\]"#

    func run(store: NoteStore) async {
        guard !isRunning, let vaultURL = store.vaultURL else { return }
        isRunning = true
        defer { isRunning = false; progress = "" }

        progress = "Scanning notes…"

        let summariesURL = vaultURL.appendingPathComponent(Self.summariesDir)
        try? FileManager.default.createDirectory(at: summariesURL,
                                                 withIntermediateDirectories: true)

        // Use only regular notes (skip existing summaries)
        let notes = store.notes

        let parents = findParentNotes(notes)
        progress = "Found \(parents.count) parent notes to summarize"

        var generated = 0
        var skipped   = 0

        for (note, children) in parents {
            let combinedText = note.resolvedContent() + children.map { $0.resolvedContent() }.joined()
            let combinedHash = sha256(combinedText)

            let stem      = note.fileURL.deletingPathExtension().lastPathComponent
            let summaryURL = summariesURL.appendingPathComponent("\(stem) Summary.md")
            let meta       = readSummaryMeta(summaryURL)

            if meta["children_hash"] == combinedHash {
                skipped += 1
                continue
            }

            let totalLen = note.resolvedContent().count + children.reduce(0) { $0 + $1.resolvedContent().count }
            if totalLen < 100 {
                skipped += 1
                continue
            }

            progress = "Summarizing \(note.title) (\(children.count) sub-notes)"

            guard let summaryText = await generateSummaryText(parent: note, children: children) else {
                continue
            }

            // Pace requests
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            let relSource = note.fileURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
            let childrenNamesJSON = (try? JSONSerialization.data(
                withJSONObject: children.map(\.title)))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"

            let summaryMD = """
            ---
            source: \(relSource)
            title: \(stem) Summary
            type: parent_summary
            children: \(childrenNamesJSON)
            children_hash: \(combinedHash)
            generated: \(df.string(from: Date()))
            ---

            # [\(stem)] Summary

            \(summaryText)
            """

            do {
                try summaryMD.write(to: summaryURL, atomically: true, encoding: .utf8)
                generated += 1
            } catch {
                continue
            }
        }

        // Clean up orphaned summaries
        let existingSources = Set(parents.map { note, _ in
            note.fileURL.path.replacingOccurrences(of: vaultURL.path + "/", with: "")
        })
        if let items = try? FileManager.default.contentsOfDirectory(
            at: summariesURL, includingPropertiesForKeys: nil) {
            for file in items where file.pathExtension == "md" {
                let meta   = readSummaryMeta(file)
                let source = meta["source"] ?? ""
                let expectedName = source.isEmpty ? "" :
                    (source as NSString).lastPathComponent
                        .replacingOccurrences(of: ".md", with: "") + " Summary.md"
                if source.isEmpty || !existingSources.contains(source) ||
                   file.lastPathComponent != expectedName {
                    try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
                }
            }
        }

        lastGenerated = generated
        progress = "Done — \(generated) generated, \(skipped) up to date"
        store.loadNotes()
    }

    // MARK: – Parent detection

    private func findParentNotes(_ notes: [Note]) -> [(Note, [Note])] {
        // Lookup by lowercased stem
        var byStem: [String: Note] = [:]
        for n in notes {
            byStem[n.fileURL.deletingPathExtension().lastPathComponent.lowercased()] = n
        }

        let tsRegex = try? NSRegularExpression(pattern: Self.timestampRE)
        let wlRegex = try? NSRegularExpression(pattern: Self.wikilinkRE)

        var result: [(Note, [Note])] = []
        for note in notes {
            let stem = note.fileURL.deletingPathExtension().lastPathComponent
            // Timestamped notes never become parents
            if let tsRegex, tsRegex.firstMatch(
                in: stem,
                range: NSRange(stem.startIndex..., in: stem)) != nil {
                continue
            }
            if stem.hasPrefix("[[") { continue }

            let text  = note.resolvedContent()
            let range = NSRange(text.startIndex..., in: text)
            let matches = wlRegex?.matches(in: text, range: range) ?? []

            var children: [Note] = []
            var seen: Set<String> = []
            for m in matches {
                guard m.numberOfRanges >= 2,
                      let r = Range(m.range(at: 1), in: text) else { continue }
                let target = String(text[r]).trimmingCharacters(in: .whitespaces).lowercased()
                guard !seen.contains(target) else { continue }
                seen.insert(target)
                if let child = byStem[target], child.fileURL != note.fileURL {
                    children.append(child)
                }
            }
            if !children.isEmpty {
                result.append((note, children))
            }
        }
        return result
    }

    // MARK: – Summary generation

    private func generateSummaryText(parent: Note, children: [Note]) async -> String? {
        var parts = ["# Parent note: \(parent.title)\n\n\(parent.resolvedContent().prefix(2000))"]
        for child in children.prefix(10) {
            parts.append("\n\n---\n## Linked note: \(child.title)\n\n\(child.resolvedContent().prefix(1500))")
        }
        let combined = parts.joined()

        let prompt = """
        You are summarizing a parent note and its linked sub-notes from a knowledge base.

        Create a comprehensive summary that:
        1. Captures the main purpose/topic of the parent note
        2. Integrates key information from linked sub-notes
        3. Extracts entities, topics, and action items across all notes

        Format your response EXACTLY like this:
        ## Summary
        <2-4 sentence overview covering parent + sub-notes>

        ## Entities
        <comma-separated: people, companies, projects>

        ## Topics
        <comma-separated>

        ## Actions
        <bullet list or 'None'>

        ## Sub-notes covered
        <bullet list of sub-note titles>

        ---

        \(combined.prefix(6000))
        """
        return await OllamaClient.shared.generateSummary(prompt: prompt)
    }

    // MARK: – Meta / helpers

    private func readSummaryMeta(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var meta: [String: String] = [:]
        for key in ["content_hash", "children_hash", "source"] {
            if let regex = try? NSRegularExpression(
                pattern: "^\(key):\\s*(.+)$",
                options: [.anchorsMatchLines]) {
                let range = NSRange(text.startIndex..., in: text)
                if let m = regex.firstMatch(in: text, range: range),
                   m.numberOfRanges >= 2,
                   let r = Range(m.range(at: 1), in: text) {
                    meta[key] = String(text[r]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return meta
    }

    private func sha256(_ s: String) -> String {
        let data = Data(s.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
