import Foundation

/// Result of a chat call — answer text + the notes cited as sources.
struct ChatResult {
    let answer:  String
    let sources: [ChatSource]
}

struct ChatSource: Identifiable, Hashable {
    let id:    UUID
    let file:  String
    let title: String

    init(id: UUID = UUID(), file: String, title: String) {
        self.id    = id
        self.file  = file
        self.title = title
    }
}

actor OllamaClient {
    static let shared = OllamaClient()
    private let base  = "http://localhost:11434"

    /// The currently selected model — mutable, persisted via UserDefaults.
    var chatModel: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "mistral-nemo" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }

    /// Fetch the list of locally available models from Ollama.
    func availableModels() async -> [String] {
        guard let url = URL(string: "\(base)/api/tags") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return models.compactMap { $0["name"] as? String }.sorted()
            }
        } catch {}
        return []
    }

    /// Switch model.
    func setModel(_ name: String) {
        UserDefaults.standard.set(name, forKey: "ollamaModel")
    }

    // MARK: – Chat with hybrid keyword+title-boosted retrieval
    //
    // Matches the spirit of design_space's `/api/chat` endpoint:
    // · builds a context string from the top-N most relevant notes,
    // · injects a strict citation-required system prompt,
    // · returns the answer and the deduplicated source list.

    /// Chat against a prebuilt vault index. The index lets us rank every note
    /// in O(n) of the in-memory dict (no file I/O), and we only read the full
    /// content of the top-K ranked files to feed the model.
    func chat(query: String, index: VaultIndex) async -> ChatResult {
        let relevant = index.rank(query: query, topK: 6)

        // Resolve each top entry's full file URL (best-effort) and load content.
        let contextParts: [String] = relevant.map { entry in
            let full = Self.loadContent(forFile: entry.file, in: index)
                      ?? entry.snippet   // fallback to snippet if file move/rename
            return """
            --- Source: \(entry.title) (file: \(entry.file)) ---
            \(full.prefix(1500))
            """
        }
        let context = contextParts.joined(separator: "\n\n")

        let systemPrompt = """
        You are a knowledgeable assistant that answers questions based on the user's Obsidian vault notes.
        RULES:
        1. Use ONLY the provided context to answer. If the context doesn't contain enough info, say so clearly.
        2. Always cite which note(s) your answer draws from using 【Note Title】 format.
        3. Be precise and thorough. Quote relevant parts when helpful.
        4. Answer in the same language the user writes in.
        5. If the question spans multiple notes, synthesize the information and cite all relevant sources.
        """

        let userContent = "Context from vault notes:\n\n\(context)\n\n---\n\nQuestion: \(query)"

        let body: [String: Any] = [
            "model": chatModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userContent]
            ],
            "stream": false
        ]

        guard let url  = URL(string: "\(base)/api/chat"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return ChatResult(answer: "⚠️ Could not form request.", sources: [])
        }

        var req            = URLRequest(url: url)
        req.httpMethod     = "POST"
        req.httpBody       = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300

        do {
            let (resp, _) = try await URLSession.shared.data(for: req)
            if let json    = try? JSONSerialization.jsonObject(with: resp) as? [String: Any],
               let msg     = json["message"] as? [String: Any],
               let content = msg["content"] as? String {
                var seen = Set<String>()
                let sources = relevant.compactMap { entry -> ChatSource? in
                    guard seen.insert(entry.file).inserted else { return nil }
                    return ChatSource(file: entry.file, title: entry.title)
                }
                return ChatResult(answer: content, sources: sources)
            }
        } catch {
            return ChatResult(answer: "⚠️ \(error.localizedDescription)", sources: [])
        }
        return ChatResult(answer: "No response from Ollama.", sources: [])
    }

    /// Load file content using the index's vaultPath. Tries the root first,
    /// falls back to a one-shot recursive lookup for files in subfolders.
    private static func loadContent(forFile file: String, in index: VaultIndex) -> String? {
        guard !index.vaultPath.isEmpty else { return nil }
        let root = URL(fileURLWithPath: index.vaultPath)
        let direct = root.appendingPathComponent(file)
        if let text = try? String(contentsOf: direct, encoding: .utf8) { return text }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == file {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }

    // MARK: – Health check

    func isRunning() async -> Bool {
        guard let url = URL(string: "\(base)/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    // MARK: – Summaries (used by SummaryEngine)

    func generateSummary(prompt: String) async -> String? {
        let body: [String: Any] = [
            "model": chatModel,
            "messages": [["role": "user", "content": prompt]],
            "stream": false
        ]
        guard let url  = URL(string: "\(base)/api/chat"),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req            = URLRequest(url: url)
        req.httpMethod     = "POST"
        req.httpBody       = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300
        do {
            let (resp, _) = try await URLSession.shared.data(for: req)
            if let json    = try? JSONSerialization.jsonObject(with: resp) as? [String: Any],
               let msg     = json["message"] as? [String: Any],
               let content = msg["content"] as? String {
                return content
            }
        } catch { return nil }
        return nil
    }
}
