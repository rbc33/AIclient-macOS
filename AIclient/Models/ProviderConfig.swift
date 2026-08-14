import Foundation

/// The wire-protocol family a provider speaks. All four backends expose an
/// OpenAI-compatible REST API (`POST /v1/chat/completions`), so a single
/// networking client (added in the Networking step) can talk to any of them.
/// We keep the distinction only so the UI can offer sensible defaults.
enum ProviderType: String, Codable, CaseIterable, Identifiable, Hashable {
    case ollama
    case nvidiaNIM
    case vllm
    case llamaCpp
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .nvidiaNIM: return "NVIDIA NIM"
        case .vllm: return "vLLM"
        case .llamaCpp: return "llama.cpp"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    /// Path appended to `baseURL` to reach the chat completions endpoint.
    /// Same for all backends today; kept per-type in case a backend diverges later.
    var defaultChatCompletionsPath: String {
        "/v1/chat/completions"
    }

    /// Whether this backend typically expects an API key. Even when true, the
    /// key stays optional in the app — most self-hosted setups behind
    /// Tailscale don't bother with one.
    var apiKeyTypicallyRequired: Bool {
        switch self {
        case .nvidiaNIM: return true
        case .ollama, .vllm, .llamaCpp, .custom: return false
        }
    }
}

/// A configured AI backend the user can chat against.
///
/// This is a plain value type — no networking and no secrets live on it.
/// The API key, if any, is stored separately in the Keychain and looked up
/// by `id` (see `Persistence/KeychainStore.swift`, added in a later step);
/// only the fact that a key *exists* (`hasAPIKey`) is persisted here.
struct ProviderConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: ProviderType
    /// e.g. `http://my-server.tailnet-1234.ts.net:11434` — a Tailscale
    /// MagicDNS name or tailnet IP, reachable without exposing anything
    /// to the public internet.
    var baseURL: URL
    var model: String
    /// Whether an API key has been saved in the Keychain for this provider.
    /// The key value itself is never stored here or in UserDefaults.
    var hasAPIKey: Bool
    /// Whether this provider is reached over Tailscale. Informational today;
    /// later steps use it to decide on ATS / local-network handling and to
    /// show a status badge (reachable / unreachable) in the provider list.
    var usesTailscale: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        type: ProviderType,
        baseURL: URL,
        model: String,
        hasAPIKey: Bool = false,
        usesTailscale: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.baseURL = baseURL
        self.model = model
        self.hasAPIKey = hasAPIKey
        self.usesTailscale = usesTailscale
        self.createdAt = createdAt
    }

    /// Full URL to the chat completions endpoint.
    var chatCompletionsURL: URL {
        baseURL.appending(path: type.defaultChatCompletionsPath)
    }
}

extension ProviderConfig {
    /// Sample data for SwiftUI previews and empty-state screenshots.
    static let example = ProviderConfig(
        name: "Home Ollama",
        type: .ollama,
        baseURL: URL(string: "http://mac-mini.tailnet-1234.ts.net:11434")!,
        model: "llama3.1:8b"
    )

    static let examples: [ProviderConfig] = [
        .example,
        ProviderConfig(
            name: "Workstation vLLM",
            type: .vllm,
            baseURL: URL(string: "http://gpu-box.tailnet-1234.ts.net:8000")!,
            model: "Qwen2.5-32B-Instruct"
        ),
        ProviderConfig(
            name: "NVIDIA NIM",
            type: .nvidiaNIM,
            baseURL: URL(string: "http://nim-server.tailnet-1234.ts.net:8000")!,
            model: "meta/llama-3.1-70b-instruct",
            hasAPIKey: true
        )
    ]
}
