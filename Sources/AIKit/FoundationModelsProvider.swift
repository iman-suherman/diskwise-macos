import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct FoundationModelsProvider: GenerativeAIProvider, Sendable {
    public let kind: AIProviderKind = .foundationModels

    public init() {}

    public func availabilityDetail() async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await MainActor.run {
                Self.detail(for: SystemLanguageModel.default.availability)
            }
        }
        #endif
        return "Requires macOS 26 with Apple Intelligence enabled."
    }

    public func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await MainActor.run {
                SystemLanguageModel.default.isAvailable
            }
        }
        #endif
        return false
    }

    public func respond(to question: String, context: AIChatContext) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await generate(
                instructions: StorageContextFormatter.chatInstructions(),
                prompt: """
                \(StorageContextFormatter.format(context))

                User question: \(question)
                """
            )
        }
        #endif
        throw AIConsultantError.providerUnavailable
    }

    public func streamRespond(to question: String, context: AIChatContext) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let instructions = StorageContextFormatter.chatInstructions()
            let prompt = """
            \(StorageContextFormatter.format(context))

            User question: \(question)
            """
            return streamGenerate(instructions: instructions, prompt: prompt)
        }
        #endif
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIConsultantError.providerUnavailable)
        }
    }

    public func suggestQuestions(context: AIChatContext) async -> [String] {
        let fallback = RuleBasedChatEngine.defaultSuggestions(for: context)
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard await isAvailable() else { return fallback }
            do {
                let response = try await generate(
                    instructions: """
                    Suggest four short follow-up questions a Mac user could ask about storage cleanup.
                    Return one question per line with no numbering.
                    """,
                    prompt: StorageContextFormatter.format(context)
                )
                let parsed = response
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return parsed.isEmpty ? fallback : Array(parsed.prefix(6))
            } catch {
                return fallback
            }
        }
        #endif
        return fallback
    }

    public func enrichAnalysis(context: AIChatContext) async throws -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let response = try await generate(
                instructions: StorageContextFormatter.analysisInstructions(),
                prompt: StorageContextFormatter.format(context)
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        #endif
        return nil
    }

    public func analyzeMemory(context: MemoryAnalysisContext) async throws -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let response = try await generate(
                instructions: MemoryContextFormatter.analysisInstructions(),
                prompt: MemoryContextFormatter.format(context)
            )
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func generate(instructions: String, prompt: String) async throws -> String {
        try await generateOnMainActor(instructions: instructions, prompt: prompt)
    }

    @available(macOS 26.0, *)
    private func streamGenerate(instructions: String, prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let stream = session.streamResponse(to: prompt)
                    var lastPartial = ""

                    for try await snapshot in stream {
                        let text = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty, text != lastPartial else { continue }
                        lastPartial = text
                        continuation.yield(text)
                    }

                    guard !lastPartial.isEmpty else {
                        throw AIConsultantError.emptyResponse
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    @available(macOS 26.0, *)
    @MainActor
    private func generateOnMainActor(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIConsultantError.emptyResponse }
        return text
    }

    @available(macOS 26.0, *)
    @MainActor
    private static func detail(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Apple Intelligence is ready on this Mac."
        case .unavailable(.deviceNotEligible):
            return "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to enable AI chat."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still preparing on this Mac."
        case .unavailable:
            return "Apple Intelligence is unavailable on this Mac."
        @unknown default:
            return "Apple Intelligence is unavailable on this Mac."
        }
    }
    #endif
}
