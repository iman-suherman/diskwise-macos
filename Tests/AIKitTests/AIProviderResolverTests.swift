import XCTest
import DatabaseKit
@testable import AIKit

final class AIProviderResolverTests: XCTestCase {
    func testAutomaticSelectsKnownProvider() async {
        let resolver = AIProviderResolver(
            configuration: AIProviderConfiguration(
                preference: .automatic,
                enableOllamaDevMode: false
            )
        )

        let status = await resolver.resolveStatus()
        XCTAssertTrue(
            [.foundationModels, .mlx, .ruleBased, .ollama].contains(status.activeProvider)
        )
    }

    func testRuleBasedPreferenceAlwaysAvailable() async {
        let resolver = AIProviderResolver(
            configuration: AIProviderConfiguration(preference: .ruleBased)
        )

        let status = await resolver.resolveStatus()
        XCTAssertEqual(status.activeProvider, .ruleBased)
        XCTAssertFalse(status.isGenerativeAvailable)
    }

    func testRuleBasedAnswersDuplicateQuestion() async throws {
        let resolver = AIProviderResolver(
            configuration: AIProviderConfiguration(preference: .ruleBased)
        )
        let report = Self.sampleReport(duplicateSavings: 2_000_000_000)
        let context = AIChatContext(report: report, topConsumers: [])

        let answer = try await resolver.respond(to: "How much duplicate space do I have?", context: context)
        XCTAssertTrue(answer.contains("duplicate"))
    }

    func testSuggestQuestionsIncludesDuplicatePromptWhenSavingsExist() async {
        let provider = RuleBasedChatProvider()
        let report = Self.sampleReport(duplicateSavings: 1_000_000)
        let context = AIChatContext(report: report, topConsumers: [])

        let suggestions = await provider.suggestQuestions(context: context)
        XCTAssertTrue(suggestions.contains(where: { $0.lowercased().contains("duplicate") }))
    }

    private static func sampleReport(duplicateSavings: Int64) -> AnalysisReport {
        AnalysisReport(
            overview: StorageOverview(
                totalSize: 500_000_000_000,
                fileCount: 1000,
                categorySummaries: [
                    CategorySummary(category: .development, totalSize: 120_000_000_000, fileCount: 42)
                ],
                duplicateSavings: duplicateSavings,
                oldFileSize: 0
            ),
            insights: [],
            recommendations: [],
            potentialReclaimableSpace: duplicateSavings
        )
    }
}
