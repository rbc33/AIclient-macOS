import SwiftUI

/// Sidebar: the conversation history, with a persistent "new conversation"
/// bar pinned at the very bottom of the window (not a toolbar icon up top).
struct ConversationListView: View {
    var conversationStore: ConversationStore
    var providerStore: ProviderStore
    @Binding var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
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
                            : "Usa el botón de abajo para empezar a chatear.")
                    }
                }
            }

            Divider()

            newConversationBar
        }
        .navigationTitle("AIclient")
    }

    private var newConversationBar: some View {
        Button(action: newConversation) {
            Label("Nueva conversación", systemImage: "square.and.pencil")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .disabled(providerStore.providers.isEmpty)
        .opacity(providerStore.providers.isEmpty ? 0.4 : 1)
        .help(providerStore.providers.isEmpty ? "Añade un proveedor primero" : "Nueva conversación")
    }

    private func newConversation() {
        guard let provider = providerStore.providers.first else { return }
        let conversation = Conversation(providerID: provider.id)
        conversationStore.upsert(conversation)
        selection = conversation.id
    }
}
