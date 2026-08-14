import Foundation

/// A chat thread against a single provider/model.
///
/// Holds the full message history plus an optional *compacted* summary of
/// older messages, so long-running conversations don't blow past the
/// model's context window. Compaction itself is implemented later (a
/// ViewModel calls out to the provider to summarize, then fills in
/// `compactedSummary`/`compactedMessageCount`) — the model just needs to be
/// able to represent the result.
struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var providerID: UUID
    var systemPrompt: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    /// Summary produced by compacting older messages. When non-nil, this is
    /// sent to the backend as a single system-role message in place of the
    /// `compactedMessageCount` messages it replaces.
    var compactedSummary: String?
    /// How many messages, counting from the start of `messages`, are folded
    /// into `compactedSummary`. Those messages stay in `messages` (so the UI
    /// can still show full history) but are skipped when building the
    /// request payload.
    var compactedMessageCount: Int

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        providerID: UUID,
        systemPrompt: String = "",
        messages: [ChatMessage] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        compactedSummary: String? = nil,
        compactedMessageCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.compactedSummary = compactedSummary
        self.compactedMessageCount = compactedMessageCount
    }

    /// Messages actually sent to the backend for the next turn: the
    /// compacted summary (if any) folded in as a leading system message,
    /// followed by the messages that haven't been compacted yet.
    var effectiveMessages: [ChatMessage] {
        let tail = Array(messages.dropFirst(compactedMessageCount))
        guard let summary = compactedSummary, !summary.isEmpty else { return tail }
        let summaryMessage = ChatMessage(
            role: .system,
            content: "Summary of earlier conversation:\n\(summary)"
        )
        return [summaryMessage] + tail
    }
}

extension Conversation {
    static let example = Conversation(
        title: "Servidores en casa",
        providerID: ProviderConfig.example.id,
        messages: ChatMessage.examples
    )
}
