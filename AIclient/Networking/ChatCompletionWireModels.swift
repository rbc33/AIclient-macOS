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
        var content: MessageContent
    }

    /// `content` in the OpenAI chat completions schema is either a plain
    /// string (what every backend accepts for text-only messages) or an
    /// array of typed parts — needed to attach images. We default to the
    /// plain string form whenever there's no image, for maximum
    /// compatibility with backends/models that only understand that shape.
    enum MessageContent: Encodable {
        case text(String)
        case parts([ContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let value):
                try container.encode(value)
            case .parts(let parts):
                try container.encode(parts)
            }
        }

        struct ContentPart: Encodable {
            var type: String
            var text: String?
            var imageURL: ImageURL?

            struct ImageURL: Encodable {
                /// A `data:<mime>;base64,<...>` URI — every backend we
                /// target (llama.cpp/llama-swap, Ollama, vLLM, NVIDIA NIM)
                /// accepts an inline data URI here, so there's no need to
                /// host the image anywhere first.
                var url: String
            }

            enum CodingKeys: String, CodingKey {
                case type, text
                case imageURL = "image_url"
            }

            static func text(_ value: String) -> ContentPart {
                ContentPart(type: "text", text: value, imageURL: nil)
            }

            static func imageURL(dataURI: String) -> ContentPart {
                ContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: dataURI))
            }
        }
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
