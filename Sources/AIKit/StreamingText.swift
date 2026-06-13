import Foundation

enum StreamingText {
    /// Yields progressively longer prefixes of `text` for providers without native streaming.
    static func simulatedReveal(
        _ text: String,
        chunkSize: Int = 3,
        delayMilliseconds: UInt64 = 18
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continuation.finish(throwing: AIConsultantError.emptyResponse)
                    return
                }

                var index = trimmed.startIndex
                while index < trimmed.endIndex {
                    let next = trimmed.index(
                        index,
                        offsetBy: chunkSize,
                        limitedBy: trimmed.endIndex
                    ) ?? trimmed.endIndex
                    let prefix = String(trimmed[..<next])
                    continuation.yield(prefix)
                    index = next
                    if index < trimmed.endIndex {
                        try? await Task.sleep(nanoseconds: delayMilliseconds * 1_000_000)
                    }
                }
                continuation.finish()
            }
        }
    }
}

public extension GenerativeAIProvider {
    func streamRespond(to question: String, context: AIChatContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let answer = try await respond(to: question, context: context)
                    for try await partial in StreamingText.simulatedReveal(answer) {
                        continuation.yield(partial)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
