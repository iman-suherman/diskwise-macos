import Foundation
import MaintenanceKit

public final class StartupAppsAnalysisEngine: @unchecked Sendable {
    private let consultant: AIConsultantService

    public init(consultant: AIConsultantService = AIConsultantService()) {
        self.consultant = consultant
    }

    public func updateConsultantConfiguration(_ configuration: AIProviderConfiguration) {
        consultant.updateConfiguration(configuration)
    }

    public func analyze(scanResult: StartupAppsScanResult) async -> StartupAppsAnalysisReport {
        let context = StartupAppsAnalysisContext(scanResult: scanResult)
        let ruleBased = RuleBasedStartupAppsEngine.analyze(items: scanResult.items)

        guard !scanResult.items.isEmpty else {
            return StartupAppsAnalysisReport(
                scannedAt: scanResult.scannedAt,
                items: [],
                analyses: [],
                summary: "No startup apps were found on this Mac."
            )
        }

        if let aiText = await consultant.analyzeStartupApps(context: context) {
            return report(from: scanResult, aiText: aiText, ruleBased: ruleBased)
        }

        return StartupAppsAnalysisReport(
            scannedAt: scanResult.scannedAt,
            items: scanResult.items,
            analyses: ruleBased,
            summary: RuleBasedStartupAppsEngine.summary(for: scanResult.items, analyses: ruleBased)
        )
    }

    public func report(
        from scanResult: StartupAppsScanResult,
        aiText: String,
        ruleBased: [StartupAppAnalysis]? = nil
    ) -> StartupAppsAnalysisReport {
        let fallback = ruleBased ?? RuleBasedStartupAppsEngine.analyze(items: scanResult.items)
        let parsed = StartupAppsAnalysisParser.parse(aiText, items: scanResult.items)
        let merged = merge(ruleBased: fallback, ai: parsed, items: scanResult.items)
        let summary = StartupAppsAnalysisParser.parseSummary(aiText)
            ?? RuleBasedStartupAppsEngine.summary(for: scanResult.items, analyses: merged)
        return StartupAppsAnalysisReport(
            scannedAt: scanResult.scannedAt,
            items: scanResult.items,
            analyses: merged,
            summary: summary
        )
    }

    public func streamAnalyze(
        scanResult: StartupAppsScanResult
    ) -> AsyncThrowingStream<String, Error> {
        let context = StartupAppsAnalysisContext(scanResult: scanResult)
        let fallback = formattedFallback(for: scanResult)
        return consultant.streamAnalyzeStartupApps(context: context, fallback: fallback)
    }

    public func providerStatus() async -> AIProviderStatus {
        await consultant.providerStatus()
    }

    private func formattedFallback(for scanResult: StartupAppsScanResult) -> String {
        let analyses = RuleBasedStartupAppsEngine.analyze(items: scanResult.items)
        let sections = zip(scanResult.items, analyses).map { item, analysis in
            """
            ## \(item.name)
            **Verdict:** \(analysis.recommendation.displayName)
            **Analysis:** \(analysis.analysis)
            """
        }
        let summary = RuleBasedStartupAppsEngine.summary(for: scanResult.items, analyses: analyses)
        return """
        \(sections.joined(separator: "\n\n"))

        ## Summary
        \(summary)
        """
    }

    private func merge(
        ruleBased: [StartupAppAnalysis],
        ai: [StartupAppAnalysis],
        items: [StartupAppItem]
    ) -> [StartupAppAnalysis] {
        items.map { item in
            ai.first { $0.itemID == item.id }
                ?? ruleBased.first { $0.itemID == item.id }
                ?? StartupAppAnalysis(
                    itemID: item.id,
                    recommendation: .optional,
                    analysis: "No analysis available for this item."
                )
        }
    }
}
