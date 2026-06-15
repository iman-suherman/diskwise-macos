import MaintenanceKit
import XCTest

final class StartupAppsScannerTests: XCTestCase {
    func testStartupAppItemGeneratesStableID() {
        let item = StartupAppItem(
            name: "DiskWise",
            path: "/Applications/DiskWise.app",
            source: .loginItem
        )
        XCTAssertEqual(item.id, "loginItem|/Applications/DiskWise.app")
    }

    func testScanResultCountsBySource() {
        let items = [
            StartupAppItem(name: "A", path: nil, source: .loginItem),
            StartupAppItem(name: "B", path: nil, source: .dockPinned),
            StartupAppItem(name: "C", path: nil, source: .launchAgent),
        ]
        let result = StartupAppsScanResult(items: items)
        XCTAssertEqual(result.loginItemCount, 1)
        XCTAssertEqual(result.dockPinnedCount, 1)
        XCTAssertEqual(result.launchAgentCount, 1)
    }
}
