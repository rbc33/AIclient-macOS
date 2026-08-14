import Foundation

enum OpenAICompatibleClientError: LocalizedError {
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "El servidor no devolvió una respuesta HTTP válida."
        case .http(let status, let body):
            return "Error HTTP \(status)\(body.isEmpty ? "" : ": \(body)")"
        }
    }
}

/// A unit of streaming progress the ViewModel folds into the active
/// `ChatMessage` as it arrives.
enum StreamEvent {
    case delta(String)
    /// `tokenCount` comes from the backend's `usage.completion_tokens` when
    /// it honors `stream_options.include_usage`; otherwise it's a rough
    /// count of received deltas (not real tokens — good enough for an
    /// approximate tokens/sec indicator, not for billing-grade accounting).
    case finished(tokenCount: Int?)
}

/// OpenAI-compatible chat completions client. Works identically against
/// Ollama, NVIDIA NIM, vLLM and llama.cpp — they all speak
/// `POST /v1/chat/completions` with SSE streaming.
///
/// Note: `ChatMessage.attachments` aren't sent to the backend yet — wiring
/// images into the OpenAI `image_url` content-part format (and deciding how
/// each backend wants PDFs/documents) is follow-up work.
struct OpenAICompatibleClient {
    func streamChatCompletion(
        provider: ProviderConfig,
        messages: [ChatMessage]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: provider.chatCompletionsURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    if provider.hasAPIKey,
                       let key = KeychainStore.apiKey(for: provider.id),
                       !key.isEmpty {
                        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }

                    let body = ChatCompletionRequest(
                        model: provider.model,
                        messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) }
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw OpenAICompatibleClientError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var collected = ""
                        for try await line in bytes.lines { collected += line }
                        throw OpenAICompatibleClientError.http(status: http.statusCode, body: collected)
                    }

                    var receivedDeltaCount = 0
                    var reportedTokenCount: Int?

                    for try await event in SSEStreamParser.events(from: bytes.lines) {
                        switch event {
                        case .chunk(let chunk):
                            if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                                receivedDeltaCount += 1
                                continuation.yield(.delta(content))
                            }
                            if let usage = chunk.usage?.completionTokens {
                                reportedTokenCount = usage
                            }
                        case .done:
                            continuation.yield(.finished(tokenCount: reportedTokenCount ?? (receivedDeltaCount > 0 ? receivedDeltaCount : nil)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
