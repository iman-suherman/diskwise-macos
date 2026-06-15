import AIKit
import MaintenanceKit
import XCTest

final class StartupAppsAnalysisTests: XCTestCase {
    func testReportBuilderParsesPerAppAnalysis() {
        let items = [
            StartupAppItem(name: "Slack", path: "/Applications/Slack.app", source: .loginItem),
            StartupAppItem(name: "Steam", path: nil, source: .loginItem, isHidden: true),
        ]
        let scanResult = StartupAppsScanResult(items: items)

        let text = """
        ## Slack
        **Verdict:** Optional
        **Analysis:** Opens the workspace at login. Disable if you only check Slack occasionally.

        ## Steam
        **Verdict:** Disable at login
        **Analysis:** Game launcher that adds boot time and background updaters.

        ## Summary
        Trim game clients and hidden login items to speed up boot.
        """

        let engine = StartupAppsAnalysisEngine()
        let report = engine.report(from: scanResult, aiText: text)
        XCTAssertEqual(report.analyses.count, 2)
        XCTAssertEqual(report.analyses.first?.recommendation, .optional)
        XCTAssertEqual(report.analyses.last?.recommendation, .disableAtLogin)
        XCTAssertEqual(report.summary, "Trim game clients and hidden login items to speed up boot.")
    }

    func testAnalyzeUsesRuleBasedFallbackWithoutAI() async {
        let items = [
            StartupAppItem(name: "Steam", path: nil, source: .loginItem, isHidden: true),
        ]
        let scanResult = StartupAppsScanResult(items: items)
        let engine = StartupAppsAnalysisEngine(
            consultant: AIConsultantService(configuration: AIProviderConfiguration(preference: .ruleBased))
        )
        let report = await engine.analyze(scanResult: scanResult)
        XCTAssertEqual(report.analyses.first?.recommendation, .disableAtLogin)
    }
}
