import DiskScannerKit
import XCTest

final class ScanScheduleAdvisorTests: XCTestCase {
    func testRecommendedScheduleUsesWeekdayMorningForFastAndSundayNightForDeep() {
        let config = ScanScheduleAdvisor.recommendedSchedule()
        XCTAssertEqual(config.fastScanHour, 6)
        XCTAssertEqual(config.fastScanWeekdays, [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(config.deepScanHour, 2)
        XCTAssertEqual(config.deepScanWeekdays, [1])
    }

    func testRecommendedScheduleWithBothEnabled() {
        let config = ScanScheduleAdvisor.recommendedScheduleWithBothEnabled()
        XCTAssertTrue(config.fastScanEnabled)
        XCTAssertTrue(config.deepScanEnabled)
    }

    func testFastScanSummaryWhenEnabled() {
        var config = ScanScheduleAdvisor.recommendedSchedule()
        config.fastScanEnabled = true
        XCTAssertTrue(ScanScheduleAdvisor.fastScanSummary(for: config).contains("Weekdays"))
        XCTAssertTrue(ScanScheduleAdvisor.fastScanSummary(for: config).contains("6"))
    }
}
