import Foundation

public actor AIProviderResolver {
    private var configuration: AIProviderConfiguration
    private let foundationModelsProvider = FoundationModelsProvider()
    private let mlxProvider = MLXProvider()
    private let ruleBasedProvider = RuleBasedChatProvider()

    public init(configuration: AIProviderConfiguration) {
        self.configuration = configuration
    }

    public func updateConfiguration(_ configuration: AIProviderConfiguration) {
        self.configuration = configuration
    }

    private func ollamaProvider() -> OllamaProvider {
        OllamaProvider(
            baseURL: configuration.ollamaBaseURL,
            model: configuration.ollamaModel
        )
    }

    public func resolveStatus() async -> AIProviderStatus {
        let provider = await resolveActiveProvider()
        let detail = await provider.availabilityDetail()
        let isGenerative = provider.kind != .ruleBased
        return AIProviderStatus(
            activeProvider: provider.kind,
            isGenerativeAvailable: isGenerative,
            displayName: provider.kind.displayName,
            detail: detail
        )
    }

    public func resolveActiveProvider() async -> any GenerativeAIProvider {
        switch configuration.preference {
        case .automatic:
            if await foundationModelsProvider.isAvailable() {
                return foundationModelsProvider
            }
            if await mlxProvider.isAvailable() {
                return mlxProvider
            }
            if configuration.enableOllamaDevMode, await ollamaProvider().isAvailable() {
                return ollamaProvider()
            }
            return ruleBasedProvider
        case .foundationModels:
            if await foundationModelsProvider.isAvailable() {
                return foundationModelsProvider
            }
            return ruleBasedProvider
        case .mlx:
            if await mlxProvider.isAvailable() {
                return mlxProvider
            }
            return ruleBasedProvider
        case .ollama:
            if configuration.enableOllamaDevMode, await ollamaProvider().isAvailable() {
                return ollamaProvider()
            }
            return ruleBasedProvider
        case .ruleBased:
            return ruleBasedProvider
        }
    }

    public func respond(to question: String, context: AIChatContext) async throws -> String {
        let provider = await resolveActiveProvider()
        if provider.kind == .ruleBased {
            return try await provider.respond(to: question, context: context)
        }
        do {
            return try await provider.respond(to: question, context: context)
        } catch {
            return try await ruleBasedProvider.respond(to: question, context: context)
        }
    }

    public func streamRespond(
        to question: String,
        context: AIChatContext
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let provider = await resolveActiveProvider()
                let stream = provider.streamRespond(to: question, context: context)
                var lastPartial = ""

                do {
                    for try await partial in stream {
                        lastPartial = partial
                        continuation.yield(partial)
                    }
                    continuation.finish()
                } catch {
                    if provider.kind != .ruleBased {
                        let fallback = RuleBasedChatEngine.answer(question: question, context: context)
                        if lastPartial.isEmpty {
                            for try await partial in StreamingText.simulatedReveal(fallback) {
                                continuation.yield(partial)
                            }
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func suggestQuestions(context: AIChatContext) async -> [String] {
        let provider = await resolveActiveProvider()
        return await provider.suggestQuestions(context: context)
    }

    public func enrichAnalysis(context: AIChatContext) async -> String? {
        if await foundationModelsProvider.isAvailable() {
            if let summary = try? await foundationModelsProvider.enrichAnalysis(context: context) {
                return summary
            }
        }
        if await mlxProvider.isAvailable() {
            if let summary = try? await mlxProvider.enrichAnalysis(context: context) {
                return summary
            }
        }
        if configuration.enableOllamaDevMode, await ollamaProvider().isAvailable() {
            if let summary = try? await ollamaProvider().enrichAnalysis(context: context) {
                return summary
            }
        }
        return nil
    }

    public func generateReport(context: AIChatContext) async throws -> String {
        if let summary = await enrichAnalysis(context: context) {
            return summary
        }
        return try await ruleBasedProvider.respond(
            to: "Summarize my storage and recommend safe cleanup steps.",
            context: context
        )
    }

    public func analyzeMemory(context: MemoryAnalysisContext) async -> String? {
        if await foundationModelsProvider.isAvailable() {
            if let summary = try? await foundationModelsProvider.analyzeMemory(context: context) {
                return summary
            }
        }
        if await mlxProvider.isAvailable() {
            if let summary = try? await mlxProvider.analyzeMemory(context: context) {
                return summary
            }
        }
        if configuration.enableOllamaDevMode, await ollamaProvider().isAvailable() {
            if let summary = try? await ollamaProvider().analyzeMemory(context: context) {
                return summary
            }
        }
        return nil
    }

    public func streamAnalyzeMemory(
        context: MemoryAnalysisContext,
        fallback: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if await foundationModelsProvider.isAvailable() {
                    let stream = foundationModelsProvider.streamAnalyzeMemory(context: context)
                    if await streamMemory(stream, to: continuation) {
                        return
                    }
                }
                if configuration.enableOllamaDevMode, await ollamaProvider().isAvailable() {
                    let stream = ollamaProvider().streamAnalyzeMemory(context: context)
                    if await streamMemory(stream, to: continuation) {
                        return
                    }
                }
                if let summary = await analyzeMemory(context: context) {
                    for try await partial in StreamingText.simulatedReveal(summary) {
                        continuation.yield(partial)
                    }
                    continuation.finish()
                    return
                }
                for try await partial in StreamingText.simulatedReveal(fallback) {
                    continuation.yield(partial)
                }
                continuation.finish()
            }
        }
    }

    public func streamRespondMemory(
        to question: String,
        context: MemoryAnalysisContext
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if await foundationModelsProvider.isAvailable() {
                    let stream = foundationModelsProvider.streamRespondMemory(to: question, context: context)
                    if await streamMemory(stream, to: continuation) {
                        return
                    }
                }
                if configuration.enableOllamaDevMode, await ollamaProvider().isAvailable() {
                    let stream = ollamaProvider().streamRespondMemory(to: question, context: context)
                    if await streamMemory(stream, to: continuation) {
                        return
                    }
                }
                let fallback = MemoryChatEngine.answer(question: question, context: context)
                for try await partial in StreamingText.simulatedReveal(fallback) {
                    continuation.yield(partial)
                }
                continuation.finish()
            }
        }
    }

    private func streamMemory(
        _ stream: AsyncThrowingStream<String, Error>,
        to continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async -> Bool {
        do {
            for try await partial in stream {
                continuation.yield(partial)
            }
            continuation.finish()
            return true
        } catch {
            return false
        }
    }
}
