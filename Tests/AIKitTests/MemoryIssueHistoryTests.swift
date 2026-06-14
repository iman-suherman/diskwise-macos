import AIKit
import XCTest

final class MemoryIssueHistoryTests: XCTestCase {
    func testIssueKeyGroupsByActionAndTarget() {
        let chrome = MemoryActionRecommendation(
            title: "Trim Google Chrome tabs",
            detail: "Many tabs open",
            actionKind: .reduceTabs,
            targetProcessName: "Google Chrome Helper (Renderer)",
            priority: 80
        )
        let chromeAgain = MemoryActionRecommendation(
            title: "Focus Google Chrome",
            detail: "Different title",
            actionKind: .reduceTabs,
            targetProcessName: "Google Chrome",
            priority: 75
        )

        XCTAssertEqual(
            MemoryIssueHistory.issueKey(for: chrome),
            MemoryIssueHistory.issueKey(for: chromeAgain)
        )
        XCTAssertEqual(MemoryIssueHistory.issueKey(for: chrome), "reduceTabs|google chrome")
    }

    func testIssueKeyUsesActionOnlyWhenNoTarget() {
        let recommendation = MemoryActionRecommendation(
            title: "Free inactive memory",
            detail: "High usage",
            actionKind: .freeMemory,
            priority: 70
        )
        XCTAssertEqual(MemoryIssueHistory.issueKey(for: recommendation), "freeMemory")
    }

    func testShouldNotifyAfterRepeatInterval() {
        let now = Date()
        let threeHoursAgo = now.addingTimeInterval(-3 * 3_600)
        XCTAssertFalse(
            MemoryIssuePatternAnalyzer.shouldNotify(
                lastNotifiedAt: threeHoursAgo,
                now: now,
                repeatInterval: 4 * 3_600
            )
        )

        let fiveHoursAgo = now.addingTimeInterval(-5 * 3_600)
        XCTAssertTrue(
            MemoryIssuePatternAnalyzer.shouldNotify(
                lastNotifiedAt: fiveHoursAgo,
                now: now,
                repeatInterval: 4 * 3_600
            )
        )
        XCTAssertTrue(MemoryIssuePatternAnalyzer.shouldNotify(lastNotifiedAt: nil, now: now))
    }

    func testSummarizeComputesIntervals() {
        let base = Date()
        let record = MemoryIssuePatternRecord(
            issueKey: "reduceTabs|google chrome",
            displayTitle: "Focus Google Chrome",
            actionKind: .reduceTabs,
            targetProcessName: "Google Chrome",
            occurrences: [
                MemoryIssueOccurrenceRecord(timestamp: base, memoryUsedPercent: 80),
                MemoryIssueOccurrenceRecord(timestamp: base.addingTimeInterval(3_600), memoryUsedPercent: 82),
                MemoryIssueOccurrenceRecord(timestamp: base.addingTimeInterval(7_200), memoryUsedPercent: 84),
            ],
            notificationCount: 1
        )

        let summary = MemoryIssuePatternAnalyzer.summarize(record)
        XCTAssertEqual(summary.occurrenceCount, 3)
        XCTAssertEqual(summary.averageInterval ?? 0, 3_600, accuracy: 0.1)
        XCTAssertEqual(summary.medianInterval ?? 0, 3_600, accuracy: 0.1)
        XCTAssertEqual(summary.typicalMemoryUsedPercent, 82, accuracy: 0.1)
    }
}
