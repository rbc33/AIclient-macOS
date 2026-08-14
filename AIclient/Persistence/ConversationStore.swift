import Foundation
import Observation

/// Persists `[Conversation]` as JSON in UserDefaults — this is the
/// "historial" of chats. Attachment bytes travel inline on each
/// `ChatMessage`, so a conversation with several images/PDFs can get large;
/// if that becomes a problem in practice, this is the file to revisit first
/// (e.g. move to on-disk JSON files or a small SQLite store).
@Observable
final class ConversationStore {
    private static let defaultsKey = "com.ricardobenthem.aiclient.conversations"

    private(set) var conversations: [Conversation] {
        didSet { persist() }
    }

    init() {
        self.conversations = Self.load().sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func load() -> [Conversation] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Conversation].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func upsert(_ conversation: Conversation) {
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    func delete(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
    }
}
