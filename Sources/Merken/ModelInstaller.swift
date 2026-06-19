import Foundation

/// One progress snapshot emitted while a model is downloading.
struct ModelPullProgress {
    let status: String
    let completedBytes: Int
    let totalBytes: Int
    /// 0.0 ... 1.0, clamped, NaN-safe.
    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(completedBytes) / Double(totalBytes)))
    }
}

/// Streams Ollama's `/api/pull` NDJSON response into per-chunk progress
/// updates. Aggregates bytes across layers so the UI sees one growing total.
enum ModelInstaller {
    /// Tags already installed locally, e.g. ["mistral-nemo:latest"].
    static func installedTags() async -> [String] {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json   = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else { return [] }
            return models.compactMap { $0["name"] as? String }
        } catch {
            return []
        }
    }

    /// Pull `tag` from the Ollama daemon, invoking `onProgress` on the main
    /// actor for each NDJSON chunk. Returns true if the daemon emitted
    /// `{"status":"success"}` before the stream closed.
    static func pull(model tag: String,
                     onProgress: @escaping @MainActor (ModelPullProgress) -> Void) async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/pull") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 600
        let body: [String: Any] = ["model": tag, "stream": true]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        req.httpBody = data

        // Per-layer maps — Ollama emits multiple layers per pull, each with
        // its own total/completed. We sum so the UI sees a single bar grow.
        var layerTotals:   [String: Int] = [:]
        var layerProgress: [String: Int] = [:]

        // Dedicated session so a bounded resource timeout applies — the per-
        // request `timeoutInterval` resets on every byte, which a slow mirror
        // can use to sit on the connection for hours.
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 60        // idle between bytes
        cfg.timeoutIntervalForResource = 60 * 60 * 2  // 2-hour ceiling per pull
        let session = URLSession(configuration: cfg)

        do {
            let (bytes, resp) = try await session.bytes(for: req)
            // Daemon error responses (404 unknown model, 500 disk full) don't
            // throw; check the HTTP status before parsing.
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let p = ModelPullProgress(status: "Ollama returned HTTP \(http.statusCode)",
                                          completedBytes: 0, totalBytes: 0)
                await MainActor.run { onProgress(p) }
                return false
            }
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let lineData = line.data(using: .utf8),
                      let json     = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    continue
                }
                if let err = json["error"] as? String {
                    let p = ModelPullProgress(status: "Error: \(err)",
                                              completedBytes: 0, totalBytes: 0)
                    await MainActor.run { onProgress(p) }
                    return false
                }
                let status = (json["status"] as? String) ?? ""
                if let digest = json["digest"] as? String {
                    // Seed completed=0 the first time we learn the layer's size
                    // — otherwise the new total bumps the denominator while
                    // `done` stays flat and the bar visibly retreats.
                    if let total = json["total"] as? Int {
                        layerTotals[digest] = total
                        if layerProgress[digest] == nil { layerProgress[digest] = 0 }
                    }
                    if let completed = json["completed"] as? Int {
                        layerProgress[digest] = completed
                    }
                }
                let total = layerTotals.values.reduce(0, +)
                let done  = layerProgress.values.reduce(0, +)
                let chunk = ModelPullProgress(status: status,
                                              completedBytes: done,
                                              totalBytes: total)
                await MainActor.run { onProgress(chunk) }
                if status == "success" { return true }
            }
            // Stream closed without "success" — treat as failure.
            return false
        } catch is CancellationError {
            return false
        } catch {
            let p = ModelPullProgress(status: "Error: \(error.localizedDescription)",
                                      completedBytes: 0, totalBytes: 0)
            await MainActor.run { onProgress(p) }
            return false
        }
    }
}
