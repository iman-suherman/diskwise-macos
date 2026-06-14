import AIKit
import XCTest

final class MemoryProcessRulesTests: XCTestCase {
    func testUserFacingApplicationNameStripsHelperSuffix() {
        XCTAssertEqual(
            MemoryProcessRules.userFacingApplicationName(for: "Google Chrome Helper (Renderer)"),
            "Google Chrome"
        )
        XCTAssertEqual(
            MemoryProcessRules.userFacingApplicationName(for: "Slack Helper (Renderer)"),
            "Slack"
        )
    }

    func testUserFacingApplicationNameKeepsMainAppName() {
        XCTAssertEqual(
            MemoryProcessRules.userFacingApplicationName(for: "Google Chrome"),
            "Google Chrome"
        )
    }

    func testIsBrowserProcessUsesNormalizedName() {
        XCTAssertTrue(MemoryProcessRules.isBrowserProcess("Google Chrome Helper (Renderer)"))
        XCTAssertFalse(MemoryProcessRules.isBrowserProcess("DiskWise"))
    }
}
