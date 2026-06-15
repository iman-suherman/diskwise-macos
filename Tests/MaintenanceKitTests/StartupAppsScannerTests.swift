@testable import MaintenanceKit
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
            StartupAppItem(name: "D", path: nil, source: .backgroundItem, isEnabled: false),
        ]
        let result = StartupAppsScanResult(items: items)
        XCTAssertEqual(result.loginItemCount, 1)
        XCTAssertEqual(result.dockPinnedCount, 1)
        XCTAssertEqual(result.launchAgentCount, 2)
    }

    func testParseBackgroundTaskManagerDumpIncludesLoginAndBackgroundApps() {
        let fixture = """
        #1:
                 Name: Slack.app
                 Type: app (0x2)
          Disposition: [disabled, allowed, notified] (0xa)
           Identifier: 2.com.tinyspeck.slackmacgap
                  URL: file:///Applications/Slack.app/
           Bundle Identifier: com.tinyspeck.slackmacgap

        #2:
                 Name: Helper.app
                 Type: login item (0x4)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 4.com.example.helper
                  URL: Contents/Library/LoginItems/Helper.app
           Bundle Identifier: com.example.helper
           Parent Identifier: 2.com.example.app

        #3:
                 Name: SpotlightItemImporter.mdimporter
                 Type: app (0x2)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 2.com.example.importer
        """

        let parsed = StartupAppsScanner().parseBackgroundTaskManagerDumpForTesting(fixture)

        XCTAssertEqual(parsed.loginItems.count, 1)
        XCTAssertEqual(parsed.backgroundApps.count, 1)
        XCTAssertEqual(parsed.backgroundApps.first?.name, "Slack")
        XCTAssertEqual(parsed.backgroundApps.first?.isEnabled, false)
        XCTAssertEqual(parsed.loginItems.first?.name, "Helper")
    }

    func testScanDiagnosticsFlagsMissingPermissions() {
        let diagnostics = StartupAppsScanDiagnostics(
            backgroundTaskManagerAccessible: false,
            automationPermissionGranted: false,
            needsAdminPassword: true
        )
        XCTAssertTrue(diagnostics.needsPermissionSetup)
    }
}
