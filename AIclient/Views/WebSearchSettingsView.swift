import SwiftUI

/// Config sheet for the app's web search capability — a single SearXNG
/// instance, not a list like `ProviderListView`, since there's normally
/// only one search backend for the whole app.
struct WebSearchSettingsView: View {
    var store: WebSearchStore

    @Environment(\.dismiss) private var dismiss

    @State private var baseURLString: String
    @State private var maxResults: Int

    private enum TestState: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
    }
    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?

    init(store: WebSearchStore) {
        self.store = store
        _baseURLString = State(initialValue: store.config?.baseURL.absoluteString ?? "http://")
        _maxResults = State(initialValue: store.config?.maxResults ?? 5)
    }

    private var isValid: Bool {
        URL(string: baseURLString) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Instancia de SearXNG") {
                    TextField("Base URL", text: $baseURLString, prompt: Text("http://searxng.tailnet.ts.net:8080"))
                        .onChange(of: baseURLString) { testState = .idle }
                    Stepper("Resultados por búsqueda: \(maxResults)", value: $maxResults, in: 1...10)

                    testRow

                    if case .failure(let message) = testState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("La app busca por su cuenta y le pasa los resultados al modelo como contexto — ningún proveedor de chat (Ollama, vLLM, llama.cpp…) navega la web por sí mismo. Necesitas una instancia de SearXNG con el formato JSON activado (añade `- json` bajo `search: formats:` en su `settings.yml`, junto a `- html`), alcanzable desde este Mac — igual que tus proveedores, va perfecto por Tailscale.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.config != nil {
                    Section {
                        Button("Desactivar búsqueda web", role: .destructive) {
                            store.clear()
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Búsqueda web")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .onDisappear { testTask?.cancel() }
    }

    private var testRow: some View {
        HStack {
            Button {
                testConnection()
            } label: {
                if testState == .testing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Probando…")
                    }
                } else {
                    Label("Probar búsqueda", systemImage: "magnifyingglass")
                }
            }
            .disabled(testState == .testing || URL(string: baseURLString) == nil)

            Spacer()

            switch testState {
            case .success(let count):
                Label("\(count) resultado\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failure:
                Label("Falló", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            case .idle, .testing:
                EmptyView()
            }
        }
    }

    /// Runs an actual test search ("prueba de conexión") since SearXNG has
    /// no lightweight health-check endpoint of its own — this also happens
    /// to verify the JSON format is enabled, not just that the server
    /// answers.
    private func testConnection() {
        guard let url = URL(string: baseURLString) else { return }
        testState = .testing
        let config = WebSearchConfig(baseURL: url, maxResults: maxResults)

        testTask?.cancel()
        testTask = Task {
            do {
                let results = try await WebSearchClient.search(query: "prueba de conexión", config: config)
                if Task.isCancelled { return }
                testState = .success(results.count)
            } catch {
                if Task.isCancelled { return }
                testState = .failure(error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let url = URL(string: baseURLString) else { return }
        store.save(WebSearchConfig(baseURL: url, maxResults: maxResults))
        dismiss()
    }
}
