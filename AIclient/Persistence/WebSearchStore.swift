import Foundation
import Observation

/// Persists the single `WebSearchConfig` (if any) as JSON in UserDefaults —
/// mirrors `ProviderStore`'s pattern, but for one config instead of a list,
/// since there's normally just one search backend for the whole app.
@Observable
final class WebSearchStore {
    private static let defaultsKey = "com.ricardobenthem.aiclient.websearch"

    private(set) var config: WebSearchConfig? {
        didSet { persist() }
    }

    init() {
        self.config = Self.load()
    }

    private static func load() -> WebSearchConfig? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WebSearchConfig.self, from: data)
    }

    private func persist() {
        guard let config else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func save(_ config: WebSearchConfig) {
        self.config = config
    }

    func clear() {
        config = nil
    }
}
