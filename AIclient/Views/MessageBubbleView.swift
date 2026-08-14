import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: ChatMessage
    /// Non-nil only for the last assistant message when it's not currently
    /// streaming — shows the "repetir" (regenerate) button.
    var onRegenerate: (() -> Void)?

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    attachmentsRow
                }

                if message.content.isEmpty && message.isStreaming {
                    Text("…")
                } else {
                    MarkdownContentView(content: message.content)
                }

                footer
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if message.role == .assistant && !message.isStreaming && (message.tokensPerSecond != nil || onRegenerate != nil) {
            HStack(spacing: 8) {
                if let tps = message.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", tps))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let onRegenerate {
                    Button(action: onRegenerate) {
                        Label("Repetir", systemImage: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Repetir la pregunta y generar otra respuesta")
                }
            }
        }
    }

    private var attachmentsRow: some View {
        let images = message.attachments.filter { $0.kind == .image }
        let others = message.attachments.filter { $0.kind != .image }

        return VStack(alignment: .leading, spacing: 6) {
            if !images.isEmpty {
                HStack(spacing: 6) {
                    ForEach(images) { attachment in
                        if let nsImage = NSImage(data: attachment.data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            if !others.isEmpty {
                HStack(spacing: 6) {
                    ForEach(others) { attachment in
                        Label(attachment.fileName, systemImage: icon(for: attachment.kind))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    private func icon(for kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(ChatMessage.examples) { MessageBubbleView(message: $0, onRegenerate: {}) }
    }
    .padding()
    .frame(width: 420)
}
