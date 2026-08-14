import Foundation

/// Response shape for the OpenAI-compatible `GET /v1/models` endpoint —
/// implemented by Ollama, vLLM and llama.cpp's server out of the box, and
/// by NVIDIA NIM as well. Used both to verify a provider is reachable and
/// to let the user pick a model instead of typing it blind.
private struct ModelsListResponse: Decodable {
    struct ModelInfo: Decodable {
        var id: String
    }
    var data: [ModelInfo]
}

enum ProviderConnectionTestResult {
    case success(models: [String])
    case failure(String)
}

enum ProviderConnectionTester {
    /// Takes `baseURL`/`apiKey` directly (not a persisted `ProviderConfig`)
    /// so the "Probar conexión" button in the edit form can test whatever
    /// the user currently has typed, before saving.
    static func testConnection(baseURL: URL, apiKey: String?) async -> ProviderConnectionTestResult {
        let modelsURL = baseURL.appending(path: "/v1/models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure("El servidor no devolvió una respuesta HTTP válida.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                return .failure("HTTP \(http.statusCode)\(bodyPreview.isEmpty ? "" : ": \(bodyPreview)")")
            }
            let decoded = try JSONDecoder().decode(ModelsListResponse.self, from: data)
            let ids = decoded.data.map(\.id).sorted()
            if ids.isEmpty {
                return .failure("Conectó, pero el servidor no listó ningún modelo.")
            }
            return .success(models: ids)
        } catch {
            return .failure("No se pudo conectar: \(error.localizedDescription)")
        }
    }
}
