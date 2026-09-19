import Foundation
import Observation

/// Owns one active `Conversation`, drives streaming via
/// `OpenAICompatibleClient`, and updates the in-flight assistant message in
/// place as SSE deltas arrive.
///
/// `@MainActor`: every mutation below touches `conversation.messages`, which
/// SwiftUI observes for the chat UI, so it all needs to happen on the main
/// actor. The network `Task` created in `beginStreaming()` inherits this
/// isolation (it's spawned from a `@MainActor` method), and only truly
/// suspends while awaiting the next SSE event — the loop body itself still
/// runs on main.
@MainActor
@Observable
final class ChatViewModel {
    var conversation: Conversation
    var provider: ProviderConfig?
    var draftText: String = ""
    var isSending = false
    var errorMessage: String?
    /// True only while a web search is in flight, before the model has
    /// started answering — lets `ChatView` show a "Buscando en la web…"
    /// status distinct from the regular streaming indicator.
    var isSearchingWeb = false

    private let store: ConversationStore
    private let webSearchStore: WebSearchStore
    private let client = OpenAICompatibleClient()
    private var streamTask: Task<Void, Never>?

    init(conversation: Conversation, provider: ProviderConfig?, store: ConversationStore, webSearchStore: WebSearchStore) {
        self.conversation = conversation
        self.provider = provider
        self.store = store
        self.webSearchStore = webSearchStore
    }

    var canRegenerate: Bool {
        !isSending && conversation.messages.contains { $0.role == .assistant }
    }

    /// - Parameter attachments: images/files picked via the "+"/paste
    ///   buttons in `ChatView`. They're attached to the outgoing user
    ///   message and shown in the transcript; the backend request itself
    ///   still only sends the text (see `OpenAICompatibleClient` — wiring
    ///   images into the `image_url` multimodal content format is
    ///   follow-up work).
    /// - Parameter webSearch: true when the "buscar en la web" toggle was on
    ///   for this message. Only takes effect if a `WebSearchConfig` is
    ///   actually saved (`ChatView`'s globe button opens Ajustes instead of
    ///   enabling the toggle when none is set, but this is a second guard).
    func send(attachments: [Attachment] = [], webSearch: Bool = false) {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty, provider != nil else { return }
        draftText = ""
        errorMessage = nil

        conversation.messages.append(ChatMessage(role: .user, content: text, attachments: attachments))

        // Auto-title new conversations from the first user message.
        if conversation.title == "New Chat" {
            if !text.isEmpty {
                conversation.title = String(text.prefix(40))
            } else if let first = attachments.first {
                conversation.title = first.fileName
            }
        }

        // Snapshot BEFORE appending the empty streaming placeholder below —
        // otherwise every request would carry a trailing empty assistant
        // message, which is not what we want to send the backend.
        let outgoing = conversation.effectiveMessages

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        conversation.messages.append(assistantMessage)

        conversation.updatedAt = .now
        persist()

        if webSearch, !text.isEmpty, let searchConfig = webSearchStore.config {
            beginStreamingWithWebSearch(query: text, outgoing: outgoing, assistantID: assistantMessage.id, config: searchConfig)
        } else {
            beginStreaming(outgoing: outgoing, assistantID: assistantMessage.id)
        }
    }

    /// Drops the last assistant response and re-asks the backend with the
    /// same conversation up to (and including) the preceding user message —
    /// the "repetir" button on the last response. Doesn't redo a web search
    /// even if the original response used one: search results are folded
    /// into the request as context only for that one call, not saved into
    /// `conversation.messages`, so a regenerate re-answers from the plain
    /// conversation history alone (and the new response won't show a
    /// "Fuentes" row).
    func regenerateLastResponse() {
        guard !isSending, provider != nil else { return }
        guard let lastAssistantIndex = conversation.messages.lastIndex(where: { $0.role == .assistant }) else { return }

        conversation.messages.removeSubrange(lastAssistantIndex...)
        errorMessage = nil

        let outgoing = conversation.effectiveMessages

        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        conversation.messages.append(assistantMessage)

        conversation.updatedAt = .now
        persist()

        beginStreaming(outgoing: outgoing, assistantID: assistantMessage.id)
    }

    func cancelStreaming() {
        streamTask?.cancel()
    }

    /// Switches this conversation to a different provider (and/or model) —
    /// called from the combined provider+model picker in `ChatView`. Updates
    /// `conversation.providerID` too, so the choice sticks the next time this
    /// conversation is opened, not just for the rest of this session.
    func setProvider(_ newProvider: ProviderConfig) {
        provider = newProvider
        conversation.providerID = newProvider.id
        conversation.updatedAt = .now
        persist()
    }

    private func beginStreaming(outgoing: [ChatMessage], assistantID: UUID) {
        guard provider != nil else { return }
        isSending = true
        streamTask = Task {
            await runStreaming(outgoing: outgoing, assistantID: assistantID)
        }
    }

    /// Fetches web search results for `query` first, folds them into
    /// `outgoing` as a leading system-role message (for this one request
    /// only — not saved into `conversation.messages`), and records the
    /// sources used onto the assistant message so `MessageBubbleView` can
    /// show a "Fuentes" row. A search failure doesn't block the chat: it
    /// falls back to answering without search context, with a note in
    /// `errorMessage`.
    private func beginStreamingWithWebSearch(query: String, outgoing: [ChatMessage], assistantID: UUID, config: WebSearchConfig) {
        guard provider != nil else { return }
        isSending = true
        isSearchingWeb = true
        streamTask = Task {
            var augmented = outgoing
            do {
                let results = try await WebSearchClient.search(query: query, config: config)
                let contextMessage = ChatMessage(
                    role: .system,
                    content: WebSearchClient.formatContext(query: query, results: results)
                )
                augmented.insert(contextMessage, at: max(augmented.count - 1, 0))
                attachSources(results.map { WebSource(title: $0.title, url: $0.url) }, toAssistantID: assistantID)
            } catch {
                if !Task.isCancelled {
                    errorMessage = "No se pudo buscar en la web (\(error.localizedDescription)) — respondiendo sin resultados de búsqueda."
                }
            }
            isSearchingWeb = false

            guard !Task.isCancelled else {
                markMessageStreamingFailed(id: assistantID, placeholderIfEmpty: false)
                isSending = false
                persist()
                return
            }
            await runStreaming(outgoing: augmented, assistantID: assistantID)
        }
    }

    private func runStreaming(outgoing: [ChatMessage], assistantID: UUID) async {
        guard let provider else { return }
        let start = Date()

        do {
            for try await event in client.streamChatCompletion(provider: provider, messages: outgoing) {
                switch event {
                case .delta(let delta):
                    appendToAssistantMessage(id: assistantID, text: delta)
                case .finished(let tokenCount):
                    finishAssistantMessage(id: assistantID, tokenCount: tokenCount, elapsed: Date().timeIntervalSince(start))
                }
            }
        } catch is CancellationError {
            // User hit stop — keep whatever partial content arrived.
            markMessageStreamingFailed(id: assistantID, placeholderIfEmpty: false)
        } catch {
            errorMessage = error.localizedDescription
            markMessageStreamingFailed(id: assistantID, placeholderIfEmpty: true)
        }
        isSending = false
        persist()
    }

    private func attachSources(_ sources: [WebSource], toAssistantID id: UUID) {
        guard let idx = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[idx].webSources = sources
    }

    private func appendToAssistantMessage(id: UUID, text: String) {
        guard let idx = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[idx].content += text
    }

    private func finishAssistantMessage(id: UUID, tokenCount: Int?, elapsed: TimeInterval) {
        guard let idx = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[idx].isStreaming = false
        conversation.messages[idx].tokenCount = tokenCount
        if let tokenCount, elapsed > 0 {
            conversation.messages[idx].tokensPerSecond = Double(tokenCount) / elapsed
        }
        conversation.updatedAt = .now
    }

    private func markMessageStreamingFailed(id: UUID, placeholderIfEmpty: Bool) {
        guard let idx = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        conversation.messages[idx].isStreaming = false
        if placeholderIfEmpty && conversation.messages[idx].content.isEmpty {
            conversation.messages[idx].content = "⚠️ No se pudo completar la respuesta."
        }
    }

    private func persist() {
        store.upsert(conversation)
    }
}
