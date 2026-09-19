import Foundation

enum WebSearchError: LocalizedError {
    case invalidResponse
    case http(Int, String)
    case emptyResults

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "El buscador no devolvió una respuesta válida."
        case .http(let code, let body):
            return "HTTP \(code)\(body.isEmpty ? "" : ": \(body)")"
        case .emptyResults:
            return "La búsqueda no encontró resultados."
        }
    }
}

/// One search result, with the snippet kept around just long enough to
/// build the context block handed to the model — only `title`/`url` get
/// persisted on the message afterwards (as `WebSource`, for the "Fuentes" UI).
struct WebSearchResult {
    var title: String
    var url: URL
    var snippet: String
}

/// Talks to a self-hosted SearXNG instance's JSON search API
/// (`GET /search?q=...&format=json`). SearXNG has that format disabled by
/// default — enable it under `search: formats:` in the instance's
/// `settings.yml` (add `- json` alongside `- html`), or every search here
/// fails with an HTTP 403.
enum WebSearchClient {
    private struct SearXNGResponse: Decodable {
        struct Result: Decodable {
            var title: String?
            var url: String?
            var content: String?
        }
        var results: [Result]
    }

    static func search(query: String, config: WebSearchConfig) async throws -> [WebSearchResult] {
        var components = URLComponents(url: config.baseURL.appending(path: "/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw WebSearchError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebSearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw WebSearchError.http(http.statusCode, String(bodyPreview))
        }

        let decoded = try JSONDecoder().decode(SearXNGResponse.self, from: data)
        let results = decoded.results.compactMap { result -> WebSearchResult? in
            guard let title = result.title, let urlString = result.url, let url = URL(string: urlString) else { return nil }
            return WebSearchResult(title: title, url: url, snippet: result.content ?? "")
        }
        guard !results.isEmpty else { throw WebSearchError.emptyResults }
        return Array(results.prefix(config.maxResults))
    }

    /// Formats results as a system-role context block handed to the model
    /// right before the user's question, e.g.:
    ///
    ///     Resultados de búsqueda web para "clima en Madrid mañana":
    ///
    ///     1. AEMET - Predicción Madrid (https://aemet.es/...)
    ///        Cielo poco nuboso, máxima de 22°C...
    ///
    ///     Usa esta información si es relevante para responder, cita las
    ///     fuentes por URL cuando la uses, y ignórala si no aporta nada a
    ///     la pregunta.
    static func formatContext(query: String, results: [WebSearchResult]) -> String {
        var lines = ["Resultados de búsqueda web para \"\(query)\":", ""]
        for (index, result) in results.enumerated() {
            lines.append("\(index + 1). \(result.title) (\(result.url.absoluteString))")
            if !result.snippet.isEmpty {
                lines.append("   \(result.snippet)")
            }
        }
        lines.append("")
        lines.append("Usa esta información si es relevante para responder, cita las fuentes por URL cuando la uses, y ignórala si no aporta nada a la pregunta.")
        return lines.joined(separator: "\n")
    }
}
