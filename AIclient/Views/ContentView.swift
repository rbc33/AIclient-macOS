import SwiftUI

struct ContentView: View {
    @State private var providerStore = ProviderStore()
    @State private var conversationStore = ConversationStore()
    @State private var webSearchStore = WebSearchStore()
    @State private var selectedConversationID: UUID?
    @State private var showingProviders = false
    @State private var showingWebSearchSettings = false

    private var selectedConversation: Conversation? {
        guard let id = selectedConversationID else { return nil }
        return conversationStore.conversations.first { $0.id == id }
    }

    var body: some View {
        NavigationSplitView {
            ConversationListView(
                conversationStore: conversationStore,
                providerStore: providerStore,
                selection: $selectedConversationID
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showingProviders = true
                    } label: {
                        Label("Proveedores", systemImage: "server.rack")
                    }
                }
                ToolbarItem(placement: .navigation) {
                    Button {
                        showingWebSearchSettings = true
                    } label: {
                        Label("Búsqueda web", systemImage: "globe")
                    }
                }
            }
        } detail: {
            if let conversation = selectedConversation {
                ChatView(
                    conversation: conversation,
                    provider: providerStore.providers.first { $0.id == conversation.providerID },
                    conversationStore: conversationStore,
                    providerStore: providerStore,
                    webSearchStore: webSearchStore
                )
                .id(conversation.id)
            } else {
                ContentUnavailableView(
                    "Selecciona o crea una conversación",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(providerStore.providers.isEmpty
                        ? "Primero añade un proveedor con el botón de arriba a la izquierda."
                        : "Usa el botón de nueva conversación en la barra lateral.")
                )
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .sheet(isPresented: $showingProviders) {
            ProviderListView(store: providerStore)
        }
        .sheet(isPresented: $showingWebSearchSettings) {
            WebSearchSettingsView(store: webSearchStore)
        }
        .onAppear {
            if providerStore.providers.isEmpty {
                showingProviders = true
            }
        }
    }
}

#Preview {
    ContentView()
}
