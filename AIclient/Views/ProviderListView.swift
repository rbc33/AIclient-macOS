import SwiftUI

struct ProviderListView: View {
    var store: ProviderStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingProvider: ProviderConfig?
    @State private var isPresentingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.providers) { provider in
                    Button {
                        editingProvider = provider
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(provider.name).font(.headline)
                                Spacer()
                                Text(provider.type.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(provider.baseURL.absoluteString) · \(provider.model)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.delete(store.providers[index])
                    }
                }
            }
            .navigationTitle("Proveedores")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNew = true
                    } label: {
                        Label("Añadir", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if store.providers.isEmpty {
                    ContentUnavailableView(
                        "Sin proveedores",
                        systemImage: "server.rack",
                        description: Text("Añade tu primer servidor Ollama, vLLM, llama.cpp o NVIDIA NIM.")
                    )
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .sheet(isPresented: $isPresentingNew) {
            ProviderEditView(store: store, provider: nil)
        }
        .sheet(item: $editingProvider) { provider in
            ProviderEditView(store: store, provider: provider)
        }
    }
}
