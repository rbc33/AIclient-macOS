import Foundation

enum MessageRole: String, Codable, Hashable {
    case system
    case user
    case assistant
}

/// A single message in a conversation.
///
/// Properties are `var` (not `let`) so the chat view model can update a
/// message in place — appending tokens to `content`, flipping `isStreaming`
/// off, setting `tokensPerSecond` — as SSE chunks arrive, without replacing
/// the array element's identity (which would break SwiftUI's diffing/animation).
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: MessageRole
    var content: String
    var attachments: [Attachment]
    let createdAt: Date

    /// True while tokens are still streaming in for this message.
    var isStreaming: Bool

    /// Tokens/sec for this message, shown as the "tokens/segundo" indicator.
    /// Set once streaming completes (or updated live, if the backend reports
    /// timing incrementally).
    var tokensPerSecond: Double?

    /// Total generated tokens. Combined with elapsed wall-clock time this
    /// lets the view model compute `tokensPerSecond` even for backends that
    /// don't report timing themselves.
    var tokenCount: Int?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String = "",
        attachments: [Attachment] = [],
        createdAt: Date = .now,
        isStreaming: Bool = false,
        tokensPerSecond: Double? = nil,
        tokenCount: Int? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.tokensPerSecond = tokensPerSecond
        self.tokenCount = tokenCount
    }
}

extension ChatMessage {
    static let examples: [ChatMessage] = [
        ChatMessage(role: .user, content: "¿Qué modelos tengo corriendo en el servidor de casa?"),
        ChatMessage(
            role: .assistant,
            content: "Según tu configuración, el proveedor **Home Ollama** está sirviendo `llama3.1:8b`.",
            tokensPerSecond: 42.3,
            tokenCount: 24
        )
    ]
}
