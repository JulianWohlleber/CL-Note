import Foundation
import Combine

// MARK: – Persistent models

struct PersistedMessage: Codable, Identifiable {
    let id:      UUID
    let role:    String          // "user" | "assistant"
    let text:    String
    let sources: [PersistedSource]
}

struct PersistedSource: Codable, Identifiable {
    let id:    UUID
    let file:  String
    let title: String
}

struct ChatSession: Codable, Identifiable {
    let id:       UUID
    var title:    String
    var messages: [PersistedMessage]
    var updatedAt: Date

    static func new() -> ChatSession {
        ChatSession(id: UUID(), title: "New chat", messages: [], updatedAt: Date())
    }
}

// MARK: – Store

@MainActor
final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published var sessions:       [ChatSession] = []
    @Published var activeSession:  ChatSession?

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Note_/chats")
    }()

    private init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
        if sessions.isEmpty { newSession() }
        else { activeSession = sessions.first }
    }

    // MARK: – CRUD

    func newSession() {
        let s = ChatSession.new()
        sessions.insert(s, at: 0)
        activeSession = s
        save(s)
    }

    func select(_ session: ChatSession) {
        activeSession = session
    }

    func delete(_ session: ChatSession) {
        let url = fileURL(session)
        try? FileManager.default.removeItem(at: url)
        sessions.removeAll { $0.id == session.id }
        if activeSession?.id == session.id {
            activeSession = sessions.first
        }
        if sessions.isEmpty { newSession() }
    }

    func append(message: PersistedMessage, to sessionID: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[idx].messages.append(message)
        sessions[idx].updatedAt = Date()
        // Auto-title from first user message
        if sessions[idx].title == "New chat",
           message.role == "user" {
            let raw = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            sessions[idx].title = String(raw.prefix(48))
        }
        if activeSession?.id == sessionID {
            activeSession = sessions[idx]
        }
        // Re-sort: most recently updated first
        sessions.sort { $0.updatedAt > $1.updatedAt }
        save(sessions[sessions.firstIndex(where: { $0.id == sessionID })!])
    }

    func rename(_ session: ChatSession, to title: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].title = title
        if activeSession?.id == session.id { activeSession = sessions[idx] }
        save(sessions[idx])
    }

    // MARK: – Persistence

    private func fileURL(_ s: ChatSession) -> URL {
        dir.appendingPathComponent("\(s.id.uuidString).json")
    }

    private func load() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [ChatSession] = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f),
               let s    = try? decoder.decode(ChatSession.self, from: data) {
                loaded.append(s)
            }
        }
        sessions = loaded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save(_ s: ChatSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(s) {
            try? data.write(to: fileURL(s), options: .atomic)
        }
    }
}

// MARK: – Bridge: PersistedMessage ↔ ChatMessage

extension PersistedMessage {
    var asChatMessage: ChatMessage {
        ChatMessage(
            id:      id,
            role:    role == "user" ? ChatMessage.Role.user : ChatMessage.Role.assistant,
            text:    text,
            sources: sources.map { ChatSource(id: $0.id, file: $0.file, title: $0.title) }
        )
    }
}

extension ChatMessage {
    var persisted: PersistedMessage {
        PersistedMessage(
            id:      id,
            role:    role == ChatMessage.Role.user ? "user" : "assistant",
            text:    text,
            sources: sources.map { PersistedSource(id: $0.id, file: $0.file, title: $0.title) }
        )
    }
}
