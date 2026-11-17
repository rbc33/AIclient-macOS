import SwiftUI

struct ProviderEditView: View {
    var store: ProviderStore
    let existing: ProviderConfig?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var type: ProviderType
    @State private var baseURLString: String
    @State private var model: String
    @State private var usesTailscale: Bool
    @State private var apiKey: String = ""
    @State private var hasSavedKey: Bool

    private enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success([String])
        case failure(String)
    }

    @State private var connectionTestState: ConnectionTestState = .idle
    @State private var testTask: Task<Void, Never>?

    init(store: ProviderStore, provider: ProviderConfig?) {
        self.store = store
        self.existing = provider
        _name = State(initialValue: provider?.name ?? "")
        _type = State(initialValue: provider?.type ?? .ollama)
        _baseURLString = State(initialValue: provider?.baseURL.absoluteString ?? "http://")
        _model = State(initialValue: provider?.model ?? "")
        _usesTailscale = State(initialValue: provider?.usesTailscale ?? true)
        _hasSavedKey = State(initialValue: provider?.hasAPIKey ?? false)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: baseURLString) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    TextField("Nombre", text: $name)
                    Picker("Tipo", selection: $type) {
                        ForEach(ProviderType.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Toggle("Vía Tailscale", isOn: $usesTailscale)
                }

                Section("Conexión") {
                    TextField("Base URL", text: $baseURLString, prompt: Text("http://mi-server.tailnet.ts.net:11434"))
                        .onChange(of: baseURLString) { connectionTestState = .idle }

                    connectionTestRow

                    if case .failure(let message) = connectionTestState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    modelField
                }

                Section("API key (opcional)") {
                    SecureField(hasSavedKey ? "Guardada en Keychain — escribe para reemplazar" : "Sin API key", text: $apiKey)
                        .onChange(of: apiKey) { connectionTestState = .idle }
                    if hasSavedKey {
                        Button("Eliminar API key guardada", role: .destructive) {
                            if let existing { store.clearAPIKey(for: existing) }
                            hasSavedKey = false
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Nuevo proveedor" : "Editar proveedor")
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
        .frame(minWidth: 460, minHeight: 480)
        .onDisappear { testTask?.cancel() }
    }

    private var connectionTestRow: some View {
        HStack {
            Button {
                testConnection()
            } label: {
                if connectionTestState == .testing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Probando…")
                    }
                } else {
                    Label("Probar conexión", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .disabled(connectionTestState == .testing || URL(string: baseURLString) == nil)

            Spacer()

            switch connectionTestState {
            case .success(let models):
                Label("\(models.count) modelo\(models.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
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

    /// The model field is a selector *only* — no free text. Until "Probar
    /// conexión" succeeds there's nothing to choose from, so we show the
    /// currently-saved model (if editing) as read-only info instead of an
    /// empty/disabled picker.
    @ViewBuilder
    private var modelField: some View {
        switch connectionTestState {
        case .success(let models):
            Picker("Modelo", selection: $model) {
                if !model.isEmpty && !models.contains(model) {
                    Text("\(model) (ya no está en la lista)").tag(model)
                }
                if model.isEmpty {
                    Text("Elegir…").tag("")
                }
                ForEach(models, id: \.self) { modelID in
                    Text(modelID).tag(modelID)
                }
            }
        case .idle, .testing, .failure:
            HStack {
                Text("Modelo")
                Spacer()
                Text(model.isEmpty ? "Prueba la conexión para elegir" : model)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func testConnection() {
        guard let url = URL(string: baseURLString) else { return }
        connectionTestState = .testing
        let keyToUse = resolvedAPIKeyForTest()

        testTask?.cancel()
        testTask = Task {
            let result = await ProviderConnectionTester.testConnection(baseURL: url, apiKey: keyToUse)
            if Task.isCancelled { return }
            switch result {
            case .success(let models):
                connectionTestState = .success(models)
            case .failure(let message):
                connectionTestState = .failure(message)
            }
        }
    }

    /// Uses whatever is currently typed in the API key field even if it
    /// hasn't been saved yet; falls back to the Keychain-stored key when
    /// editing an existing provider and the field is untouched.
    private func resolvedAPIKeyForTest() -> String? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if hasSavedKey, let existing { return KeychainStore.apiKey(for: existing.id) }
        return nil
    }

    private func save() {
        guard let url = URL(string: baseURLString) else { return }
        var provider = existing ?? ProviderConfig(name: name, type: type, baseURL: url, model: model, usesTailscale: usesTailscale)
        provider.name = name
        provider.type = type
        provider.baseURL = url
        provider.model = model
        provider.usesTailscale = usesTailscale

        store.upsert(provider)

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        if !trimmedKey.isEmpty {
            store.saveAPIKey(trimmedKey, for: provider)
        }

        dismiss()
    }
}
