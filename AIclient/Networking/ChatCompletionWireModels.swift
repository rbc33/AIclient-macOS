import Foundation

/// Request body for `POST /v1/chat/completions`, the shape shared by
/// Ollama, NVIDIA NIM, vLLM and llama.cpp's OpenAI-compatible servers.
struct ChatCompletionRequest: Encodable {
    var model: String
    var messages: [RequestMessage]
    var stream: Bool = true
    /// Asks the backend to emit a final SSE chunk carrying token usage, so
    /// we can report real tokens/sec instead of the delta-count fallback.
    /// Backends that don't understand this field simply ignore it.
    var streamOptions: StreamOptions? = StreamOptions(includeUsage: true)

    struct RequestMessage: Encodable {
        var role: String
        var content: String
    }

    struct StreamOptions: Encodable {
        var includeUsage: Bool
        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case streamOptions = "stream_options"
    }
}

/// One decoded `data: {...}` SSE payload from a streaming chat completion.
struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var role: String?
            var content: String?
        }
        var delta: Delta
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    var choices: [Choice]
    var usage: Usage?
}
