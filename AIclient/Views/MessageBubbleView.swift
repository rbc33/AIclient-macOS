import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: ChatMessage
    /// Non-nil only for the last assistant message when it's not currently
    /// streaming — shows the "repetir" (regenerate) button.
    var onRegenerate: (() -> Void)?

    @State private var didCopy = false
    @State private var isHovering = false

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
            // Assistant responses blend into the window background (no
            // bubble box) — only the user's own messages get a tinted bubble.
            .background(isUser ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onHover { hovering in isHovering = hovering }

            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if message.role == .assistant && !message.isStreaming {
            HStack(spacing: 10) {
                Button {
                    copyToClipboard()
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copiar la respuesta")

                if let onRegenerate {
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Repetir la pregunta y generar otra respuesta")
                }

                if let tps = message.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", tps))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .font(.caption2)
            // Only visible on hover, but still laid out (opacity, not
            // conditional content) so the bubble doesn't jump in height.
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message.content, forType: .string)

        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
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
        case .audio: return "waveform"
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
