import SwiftUI

/// Sidebar: the conversation history, plus the entry point for starting a
/// new chat against the first available provider.
///
/// The "new conversation" action is offered two ways on purpose: a toolbar
/// icon (fast, once you have conversations already) *and* a full-size
/// button inside the empty-state view. macOS's `NavigationSplitView`
/// toolbar-merging across columns can be finicky about where/whether a
/// column's toolbar items actually render, so the empty-state button is the
/// guaranteed-visible fallback — it's plain view content, not a toolbar item.
struct ConversationListView: View {
    var conversationStore: ConversationStore
    var providerStore: ProviderStore
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            ForEach(conversationStore.conversations) { conversation in
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(conversation.messages.last?.content ?? "Sin mensajes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(conversation.id)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    conversationStore.delete(conversationStore.conversations[index])
                }
            }
        }
        .overlay {
            if conversationStore.conversations.isEmpty {
                ContentUnavailableView {
                    Label("Sin conversaciones", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text(providerStore.providers.isEmpty
                        ? "Añade un proveedor primero (arriba a la izquierda)."
                        : "Crea tu primera conversación para empezar a chatear.")
                } actions: {
                    Button("Nueva conversación", action: newConversation)
                        .disabled(providerStore.providers.isEmpty)
                }
            }
        }
        .navigationTitle("AIclient")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newConversation()
                } label: {
                    Label("Nueva conversación", systemImage: "square.and.pencil")
                }
                .disabled(providerStore.providers.isEmpty)
                .help(providerStore.providers.isEmpty ? "Añade un proveedor primero" : "Nueva conversación")
            }
        }
    }

    private func newConversation() {
        guard let provider = providerStore.providers.first else { return }
        let conversation = Conversation(providerID: provider.id)
        conversationStore.upsert(conversation)
        selection = conversation.id
    }
}
