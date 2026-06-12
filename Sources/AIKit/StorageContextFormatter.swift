import Foundation
import DatabaseKit

enum StorageContextFormatter {
    static func format(_ context: AIChatContext) -> String {
        let report = context.report
        let categories = report.overview.categorySummaries
            .prefix(8)
            .map { "\($0.category.displayName): \(ByteCountFormatter.string(fromByteCount: $0.totalSize, countStyle: .file)) (\($0.fileCount) files)" }
            .joined(separator: "\n")

        let consumers = context.topConsumers
            .prefix(6)
            .map { "- \($0.name): \(ByteCountFormatter.string(fromByteCount: $0.totalSize, countStyle: .file))" }
            .joined(separator: "\n")

        let insights = report.insights
            .prefix(8)
            .map { "- \($0.title): \(ByteCountFormatter.string(fromByteCount: $0.estimatedSavings, countStyle: .file)) — \($0.detail)" }
            .joined(separator: "\n")

        let recommendations = report.recommendations
            .prefix(8)
            .map { "- \($0.title): \($0.reason)" }
            .joined(separator: "\n")

        return """
        DiskWise storage scan summary:
        Total indexed: \(ByteCountFormatter.string(fromByteCount: report.overview.totalSize, countStyle: .file))
        Potential reclaimable: \(ByteCountFormatter.string(fromByteCount: report.potentialReclaimableSpace, countStyle: .file))
        Duplicate savings: \(ByteCountFormatter.string(fromByteCount: report.overview.duplicateSavings, countStyle: .file))

        Top categories:
        \(categories)

        Largest folders:
        \(consumers)

        Insights:
        \(insights)

        Recommendations:
        \(recommendations)
        """
    }

    static func chatInstructions() -> String {
        """
        You are DiskWise, a privacy-first macOS storage consultant.
        Answer using only the provided scan data.
        Be concise, practical, and safety-conscious.
        Prefer bullet lists for cleanup suggestions.
        Never recommend deleting personal photos or documents without review.
        """
    }

    static func analysisInstructions() -> String {
        """
        You are DiskWise, a privacy-first macOS storage consultant.
        Write a short executive summary explaining why the disk is full and what can be cleaned safely.
        Use plain language, 2-4 short paragraphs, and mention the largest categories and folders.
        """
    }
}
