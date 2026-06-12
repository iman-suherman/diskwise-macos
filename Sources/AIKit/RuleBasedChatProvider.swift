import Foundation

public struct RuleBasedChatProvider: GenerativeAIProvider, Sendable {
    public let kind: AIProviderKind = .ruleBased

    public init() {}

    public func availabilityDetail() async -> String {
        "Uses scan rules and keyword matching."
    }

    public func isAvailable() async -> Bool { true }

    public func respond(to question: String, context: AIChatContext) async throws -> String {
        RuleBasedChatEngine.answer(question: question, context: context)
    }

    public func suggestQuestions(context: AIChatContext) async -> [String] {
        RuleBasedChatEngine.defaultSuggestions(for: context)
    }

    public func enrichAnalysis(context: AIChatContext) async throws -> String? {
        nil
    }
}

enum RuleBasedChatEngine {
    static let defaultSuggestions = [
        "What is consuming most of my disk?",
        "Can I safely remove anything?",
        "Why is my SSD almost full?",
        "Find old videos I haven't watched.",
    ]

    static func defaultSuggestions(for context: AIChatContext) -> [String] {
        var suggestions = defaultSuggestions
        if context.report.overview.duplicateSavings > 0 {
            suggestions.insert("How much space can I reclaim from duplicates?", at: 1)
        }
        if context.report.insights.contains(where: { $0.title == "Developer artifacts" }) {
            suggestions.append("Should I purge DerivedData and Docker caches?")
        }
        return Array(suggestions.prefix(6))
    }

    static func answer(question: String, context: AIChatContext) -> String {
        let lower = question.lowercased()
        let report = context.report
        let consumers = context.topConsumers
        let bytes = ByteCountFormatter()
        bytes.countStyle = .file

        if lower.contains("most") || lower.contains("consuming") || lower.contains("full") {
            if let top = consumers.first {
                let categories = report.overview.categorySummaries.prefix(3)
                    .map { "\($0.category.displayName): \(bytes.string(fromByteCount: $0.totalSize))" }
                    .joined(separator: ", ")
                return "Your biggest space consumer is \(top.name) at \(bytes.string(fromByteCount: top.totalSize)). Top categories: \(categories)."
            }
        }

        if lower.contains("safely") || lower.contains("remove") || lower.contains("delete") {
            let recs = report.recommendations.prefix(4)
                .map { "• \($0.title) — save \(bytes.string(fromByteCount: $0.estimatedSavings))" }
                .joined(separator: "\n")
            return "Based on your scan, these are safe starting points:\n\(recs)\n\nAlways preview before moving files to Trash."
        }

        if lower.contains("duplicate") {
            let savings = report.overview.duplicateSavings
            return savings > 0
                ? "I found \(bytes.string(fromByteCount: savings)) in duplicate files. Open the Duplicates tab to review groups and clean up safely."
                : "No significant duplicate files were detected in the latest scan."
        }

        if lower.contains("video") || lower.contains("watch") {
            let mediaSize = report.overview.categorySummaries
                .filter { $0.category == .video || $0.category == .photo }
                .reduce(Int64(0)) { $0 + $1.totalSize }
            return "Media files use \(bytes.string(fromByteCount: mediaSize)). Check the Overview for your largest folders and consider archiving old exports."
        }

        if lower.contains("cache") || lower.contains("derived") || lower.contains("docker") {
            let devInsight = report.insights.first(where: { $0.title == "Developer artifacts" || $0.title == "Cache files" })
            if let devInsight, devInsight.estimatedSavings > 0 {
                return "\(devInsight.title) use \(bytes.string(fromByteCount: devInsight.estimatedSavings)). \(devInsight.detail) Use Maintenance for targeted cleanup."
            }
        }

        let reclaimable = bytes.string(fromByteCount: report.potentialReclaimableSpace)
        return "You could potentially reclaim \(reclaimable). Top insight: \(report.insights.first?.title ?? "Run a scan for detailed analysis."). Try asking about duplicates, caches, or what's using the most space."
    }
}
