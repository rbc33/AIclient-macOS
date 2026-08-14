import Foundation

/// A decoded Server-Sent-Events payload from an OpenAI-compatible streaming
/// chat completion response.
enum SSEEvent {
    case chunk(ChatCompletionChunk)
    case done
}

enum SSEStreamParser {
    /// Turns raw SSE lines (`URLSession.AsyncBytes.lines`) into decoded
    /// `SSEEvent`s. Ignores blank lines and anything that isn't a `data:`
    /// field — OpenAI-compatible servers only ever send `data:` lines that
    /// matter here (no custom `event:`/`id:` fields to track).
    static func events(from lines: AsyncLineSequence<URLSession.AsyncBytes>) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" {
                            continuation.yield(.done)
                            continue
                        }
                        guard let data = payload.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
                        continuation.yield(.chunk(chunk))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
