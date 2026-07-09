import Foundation

/// A single note's entry in the persistent search index.
///
/// Purpose: the chat / AI code needs to rank notes by relevance to a query
/// without reading every file on every request. Each entry stores just enough
/// to score cheaply: the title, a body snippet, and wikilink targets.
struct IndexEntry: Codable, Hashable {
    var file:         String          // lastPathComponent
    var title:        String
    var modified:     Date
    var size:         Int             // file size in bytes
    var snippet:      String          // first ~1200 chars of body (no front-matter noise)
    var wikilinks:    [String]        // targets referenced via [[...]]
}

/// On-disk search index for a single vault.
///
/// Stored as JSON in Application Support so it survives relaunches. The store
/// keeps an in-memory copy and rebuilds it incrementally in the background,
/// only touching files whose modified-date or size changed since last scan.
struct VaultIndex: Codable {
    var vaultPath: String
    var entries:   [String: IndexEntry]   // key: lastPathComponent

    static func empty(vaultPath: String) -> VaultIndex {
        VaultIndex(vaultPath: vaultPath, entries: [:])
    }

    /// Where this vault's index lives on disk.
    static func url(forVaultID id: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
            .appendingPathComponent("Note_")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("index-\(id).json")
    }

    static func load(fromVaultID id: String) -> VaultIndex? {
        let url = url(forVaultID: id)
        guard let data = try? Data(contentsOf: url),
              let idx  = try? JSONDecoder().decode(VaultIndex.self, from: data) else {
            return nil
        }
        return idx
    }

    func save(vaultID: String) {
        let url = Self.url(forVaultID: vaultID)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url)
        }
    }

    // MARK: – Building entries from raw files

    /// Build an entry by reading the file. Content is discarded afterwards.
    static func makeEntry(fileURL: URL,
                          modified: Date,
                          size: Int) -> IndexEntry? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        // Strip simple YAML front-matter so the snippet isn't wasted on metadata.
        var body = text
        if body.hasPrefix("---\n"),
           let end = body.range(of: "\n---\n", range: body.index(body.startIndex, offsetBy: 4)..<body.endIndex) {
            body = String(body[end.upperBound...])
        }
        let snippet = String(body.prefix(1200))

        // Extract [[wikilink]] targets (ignoring |alias)
        var wikilinks: [String] = []
        let wlRE = try? NSRegularExpression(pattern: #"\[\[([^\]\n|]+?)(?:\|[^\]\n]+)?\]\]"#)
        let range  = NSRange(text.startIndex..., in: text)
        wlRE?.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2,
                  let r = Range(m.range(at: 1), in: text) else { return }
            wikilinks.append(String(text[r]).trimmingCharacters(in: .whitespaces))
        }

        return IndexEntry(
            file:      fileURL.lastPathComponent,
            title:     fileURL.deletingPathExtension().lastPathComponent,
            modified:  modified,
            size:      size,
            snippet:   snippet,
            wikilinks: wikilinks
        )
    }

    // MARK: – Ranking

    /// Score every entry against a query and return the top K.
    /// Uses title, snippet, and wikilink targets with weighted scoring.
    func rank(query: String, topK: Int = 6) -> [IndexEntry] {
        let stopWords: Set<String> = [
            "the","and","for","with","that","this","have","are","was","were",
            "from","you","your","all","but","not","what","when","how","why",
            "who","where","can","could","would","should","has","had","been"
        ]
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        if words.isEmpty {
            return entries.values
                .sorted { $0.modified > $1.modified }
                .prefix(topK)
                .map { $0 }
        }

        func score(_ e: IndexEntry) -> Double {
            let title   = e.title.lowercased()
            let snippet = e.snippet.lowercased()
            let links   = e.wikilinks.joined(separator: " ").lowercased()
            var titleHits = 0, bodyHits = 0, linkHits = 0
            for w in words {
                if title.contains(w)   { titleHits += 1 }
                if snippet.contains(w) { bodyHits  += 1 }
                if links.contains(w)   { linkHits  += 1 }
            }
            // Titles weigh heaviest, wikilink relationships next, body last.
            return 3.0 * Double(titleHits) + 1.5 * Double(linkHits) + Double(bodyHits)
        }

        return entries.values
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
    }
}
