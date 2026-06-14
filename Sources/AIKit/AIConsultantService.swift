import Foundation
import DatabaseKit

public struct OllamaConfiguration: Sendable {
    public let baseURL: URL
    public let model: String

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, model: String = "llama3.1") {
        self.baseURL = baseURL
        self.model = model
    }
}

public final class AIConsultantService: @unchecked Sendable {
    private let resolver: AIProviderResolver

    public init(configuration: AIProviderConfiguration = AIProviderConfiguration()) {
        self.resolver = AIProviderResolver(configuration: configuration)
    }

    public func updateConfiguration(_ configuration: AIProviderConfiguration) {
        Task { await resolver.updateConfiguration(configuration) }
    }

    public func providerStatus() async -> AIProviderStatus {
        await resolver.resolveStatus()
    }

    public func respond(to question: String, context: AIChatContext) async throws -> String {
        try await resolver.respond(to: question, context: context)
    }

    public func streamRespond(
        to question: String,
        context: AIChatContext
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let stream = await resolver.streamRespond(to: question, context: context)
                do {
                    for try await partial in stream {
                        continuation.yield(partial)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func suggestQuestions(context: AIChatContext) async -> [String] {
        await resolver.suggestQuestions(context: context)
    }

    public func enrichAnalysis(context: AIChatContext) async -> String? {
        await resolver.enrichAnalysis(context: context)
    }

    public func analyzeMemory(context: MemoryAnalysisContext) async -> String? {
        await resolver.analyzeMemory(context: context)
    }

    public func generateReport(context: AIChatContext) async throws -> String {
        try await resolver.generateReport(context: context)
    }

    public func autocompleteSuggestions(for partialQuestion: String, context: AIChatContext) async -> [String] {
        let trimmed = partialQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return await suggestQuestions(context: context)
        }

        let suggestions = await suggestQuestions(context: context)
        let lower = trimmed.lowercased()
        let filtered = suggestions.filter { $0.lowercased().contains(lower) || lower.contains($0.lowercased().prefix(8)) }
        if !filtered.isEmpty {
            return filtered
        }

        let status = await providerStatus()
        guard status.isGenerativeAvailable else { return [] }

        let completionSeed = trimmed.hasSuffix(" ") ? trimmed : trimmed + " "
        return suggestions
            .map { suggestion in
                suggestion.lowercased().hasPrefix(lower)
                    ? suggestion
                    : completionSeed + suggestion
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
            .map { String($0) }
    }
}
