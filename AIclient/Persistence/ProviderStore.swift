import Foundation
import Observation

/// Persists `[ProviderConfig]` as JSON in UserDefaults and keeps API keys in
/// sync with `KeychainStore`. Views read `providers` directly (it's
/// `@Observable`) — nothing else should touch `UserDefaults` for providers.
@Observable
final class ProviderStore {
    private static let defaultsKey = "com.ricardobenthem.aiclient.providers"

    private(set) var providers: [ProviderConfig] {
        didSet { persist() }
    }

    init() {
        self.providers = Self.load()
    }

    private static func load() -> [ProviderConfig] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([ProviderConfig].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func upsert(_ provider: ProviderConfig) {
        if let idx = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[idx] = provider
        } else {
            providers.append(provider)
        }
    }

    func delete(_ provider: ProviderConfig) {
        providers.removeAll { $0.id == provider.id }
        KeychainStore.deleteAPIKey(for: provider.id)
    }

    func saveAPIKey(_ key: String, for provider: ProviderConfig) {
        KeychainStore.save(apiKey: key, for: provider.id)
        guard var updated = providers.first(where: { $0.id == provider.id }) else { return }
        updated.hasAPIKey = true
        upsert(updated)
    }

    func clearAPIKey(for provider: ProviderConfig) {
        KeychainStore.deleteAPIKey(for: provider.id)
        guard var updated = providers.first(where: { $0.id == provider.id }) else { return }
        updated.hasAPIKey = false
        upsert(updated)
    }
}
