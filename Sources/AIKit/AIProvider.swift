import Foundation
import DatabaseKit

public enum AIProviderKind: String, Sendable, CaseIterable, Identifiable {
    case automatic
    case foundationModels
    case mlx
    case ollama
    case ruleBased

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .foundationModels: return "Apple Intelligence"
        case .mlx: return "Local MLX Model"
        case .ollama: return "Ollama"
        case .ruleBased: return "Rule-based"
        }
    }
}

public struct AIProviderStatus: Sendable, Equatable {
    public let activeProvider: AIProviderKind
    public let isGenerativeAvailable: Bool
    public let displayName: String
    public let detail: String

    public init(
        activeProvider: AIProviderKind,
        isGenerativeAvailable: Bool,
        displayName: String,
        detail: String
    ) {
        self.activeProvider = activeProvider
        self.isGenerativeAvailable = isGenerativeAvailable
        self.displayName = displayName
        self.detail = detail
    }

    public static let unavailable = AIProviderStatus(
        activeProvider: .ruleBased,
        isGenerativeAvailable: false,
        displayName: "Rule-based insights",
        detail: "Scan a drive to get storage recommendations. Apple Intelligence is not available on this Mac."
    )
}

public struct AIChatContext: Sendable {
    public let report: AnalysisReport
    public let topConsumers: [SpaceConsumer]

    public init(report: AnalysisReport, topConsumers: [SpaceConsumer]) {
        self.report = report
        self.topConsumers = topConsumers
    }
}

public struct AIProviderConfiguration: Sendable {
    public var preference: AIProviderKind
    public var ollamaBaseURL: URL
    public var ollamaModel: String
    public var enableOllamaDevMode: Bool

    public init(
        preference: AIProviderKind = .automatic,
        ollamaBaseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        ollamaModel: String = "llama3.1",
        enableOllamaDevMode: Bool = false
    ) {
        self.preference = preference
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModel = ollamaModel
        self.enableOllamaDevMode = enableOllamaDevMode
    }
}

public protocol GenerativeAIProvider: Sendable {
    var kind: AIProviderKind { get }
    func availabilityDetail() async -> String
    func isAvailable() async -> Bool
    func respond(to question: String, context: AIChatContext) async throws -> String
    func suggestQuestions(context: AIChatContext) async -> [String]
    func enrichAnalysis(context: AIChatContext) async throws -> String?
}

public enum AIConsultantError: LocalizedError, Sendable {
    case providerUnavailable
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "No AI provider is available right now."
        case .emptyResponse:
            return "The AI provider returned an empty response."
        }
    }
}
