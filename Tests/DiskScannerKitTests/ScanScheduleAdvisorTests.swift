import DiskScannerKit
import XCTest

final class ScanScheduleAdvisorTests: XCTestCase {
    func testRecommendedEntriesUseWeekdayMorningForFastAndSundayNightForDeep() {
        let entries = ScanScheduleAdvisor.recommendedEntries()
        let fast = entries.first { $0.mode == .fast }
        let deep = entries.first { $0.mode == .deep }
        XCTAssertEqual(fast?.hour, 6)
        XCTAssertEqual(fast?.weekdays, [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(deep?.hour, 2)
        XCTAssertEqual(deep?.weekdays, [1])
    }

    func testRecommendedScheduleWithBothEnabled() {
        let config = ScanScheduleAdvisor.recommendedScheduleWithBothEnabled()
        XCTAssertTrue(config.hasEnabledEntries)
        XCTAssertEqual(config.entries.filter(\.isEnabled).count, 2)
    }

    func testEntrySummaryWhenEnabled() {
        var entry = ScanScheduleAdvisor.recommendedEntries().first { $0.mode == .fast }!
        entry.isEnabled = true
        XCTAssertTrue(ScanScheduleAdvisor.entrySummary(entry).contains("Weekdays"))
    }

    func testLegacyConfigDecodesIntoEntries() throws {
        let legacyJSON = """
        {"fastScanEnabled":true,"deepScanEnabled":false,"fastScanHour":7,"fastScanWeekdays":[2,3],"deepScanHour":2,"deepScanWeekdays":[1]}
        """
        let data = Data(legacyJSON.utf8)
        let config = try JSONDecoder().decode(VolumeScanScheduleConfig.self, from: data)
        XCTAssertEqual(config.entries.count, 2)
        XCTAssertTrue(config.entry(for: .fast)?.isEnabled == true)
        XCTAssertFalse(config.entry(for: .deep)?.isEnabled == true)
        XCTAssertEqual(config.entry(for: .fast)?.hour, 7)
    }
}
