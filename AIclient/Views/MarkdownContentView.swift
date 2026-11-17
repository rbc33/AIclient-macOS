import SwiftUI

/// Lightweight Markdown rendering for chat bubbles, without a third-party
/// dependency:
///
/// - Fenced ``` code blocks are split out and rendered in a monospaced,
///   shaded block (the single most useful thing to get right for an
///   AI-coding chat client).
/// - Everything else goes through `AttributedString`'s built-in Markdown
///   parser (`.full` interpreted syntax), which gives bold/italic/inline
///   code/links, and — via `Text`'s native support for `PresentationIntent`
///   — headings and lists too.
struct MarkdownContentView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                if segment.isCode {
                    codeBlock(segment)
                } else if !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(attributed(segment.text))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func codeBlock(_ segment: Segment) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(segment.text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))
    }

    private func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: - Fenced code block splitting

    private struct Segment: Identifiable {
        let id = UUID()
        let isCode: Bool
        let text: String
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var current: [String] = []
        var inCode = false

        func flush(isCode: Bool) {
            guard !current.isEmpty else { return }
            result.append(Segment(isCode: isCode, text: current.joined(separator: "\n")))
            current = []
        }

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                flush(isCode: inCode)
                inCode.toggle()
                continue
            }
            current.append(line)
        }
        // Unterminated fence (response still streaming in) — show what we
        // have so far rather than losing it.
        flush(isCode: inCode)
        return result
    }
}

#Preview {
    MarkdownContentView(content: """
    Aquí tienes un ejemplo con **negrita**, _cursiva_ y `código inline`.

    - primero
    - segundo

    ```swift
    struct Foo {
        let bar: Int
    }
    ```

    Y texto normal después.
    """)
    .padding()
    .frame(width: 420)
}
