import Foundation
import AppKit

/// Helpers for detecting and bootstrapping the Ollama daemon.
///
/// The macOS path is: official Ollama.app is dragged into /Applications and
/// launched; the menu-bar app starts the daemon on http://localhost:11434.
/// We never silently install — the .dmg requires an admin prompt for the CLI
/// shim, which we can't reasonably automate from a sandboxed app.
enum OllamaInstaller {
    static let downloadURL = URL(string: "https://ollama.com/download/Ollama.dmg")!

    /// Candidate install locations: system Applications + per-user Applications
    /// (the default for non-admin installs).
    private static var candidatePaths: [String] {
        var paths = ["/Applications/Ollama.app"]
        if let user = FileManager.default.urls(for: .applicationDirectory,
                                               in: .userDomainMask).first {
            paths.append(user.appendingPathComponent("Ollama.app").path)
        }
        return paths
    }

    /// Ping `/api/version`. Returns the daemon version string on success, nil
    /// if the daemon isn't reachable within `timeout`.
    static func daemonVersion(timeout: TimeInterval = 1.5) async -> String? {
        guard let url = URL(string: "http://localhost:11434/api/version") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let v    = json["version"] as? String else { return nil }
            return v
        } catch {
            return nil
        }
    }

    static func installedAppPath() -> String? {
        candidatePaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func appIsInstalled() -> Bool { installedAppPath() != nil }

    /// If Ollama.app is already on disk anywhere we look, launch it.
    /// Otherwise send the user to the official download page.
    static func launchOrInstall() {
        if let path = installedAppPath() {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            NSWorkspace.shared.open(downloadURL)
        }
    }
}
