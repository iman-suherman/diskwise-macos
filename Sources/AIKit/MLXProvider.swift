import Foundation

public struct MLXProvider: GenerativeAIProvider, Sendable {
    public let kind: AIProviderKind = .mlx

    private let modelDirectory: URL

    public init(modelDirectory: URL? = nil) {
        if let modelDirectory {
            self.modelDirectory = modelDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            self.modelDirectory = appSupport?
                .appendingPathComponent("DiskWise/Models/MLX", isDirectory: true)
                ?? URL(fileURLWithPath: "/tmp/diskwise-mlx")
        }
    }

    public func availabilityDetail() async -> String {
        if installedModelURL() != nil {
            return "MLX model found in Application Support."
        }
        return "Download a Qwen3 4B MLX model to enable advanced local analysis."
    }

    public func isAvailable() async -> Bool {
        installedModelURL() != nil
    }

    public func respond(to question: String, context: AIChatContext) async throws -> String {
        throw AIConsultantError.providerUnavailable
    }

    public func suggestQuestions(context: AIChatContext) async -> [String] {
        RuleBasedChatEngine.defaultSuggestions(for: context)
    }

    public func enrichAnalysis(context: AIChatContext) async throws -> String? {
        nil
    }

    public func analyzeMemory(context: MemoryAnalysisContext) async throws -> String? {
        nil
    }

    private func installedModelURL() -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        return contents.first { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".mlx") || name.hasSuffix(".safetensors") || name.hasSuffix(".json")
        }
    }
}
