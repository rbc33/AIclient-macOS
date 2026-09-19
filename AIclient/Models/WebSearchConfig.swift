import Foundation

/// Config for the app's own web search capability — used to give
/// OpenAI-compatible backends (which don't browse the web themselves)
/// external context before they answer. Points at a self-hosted SearXNG
/// instance (a meta search engine you run yourself, reachable over
/// Tailscale just like the model providers), not a third-party paid API.
struct WebSearchConfig: Codable, Hashable {
    /// e.g. `http://searxng.tailnet-1234.ts.net:8080` — the instance must
    /// have JSON output enabled (SearXNG disables it by default; add
    /// `- json` under `search: formats:` in its `settings.yml`, alongside
    /// `- html`), or every search here fails with an HTTP 403.
    var baseURL: URL
    /// How many results to fetch and hand to the model as context.
    var maxResults: Int

    init(baseURL: URL, maxResults: Int = 5) {
        self.baseURL = baseURL
        self.maxResults = maxResults
    }
}
