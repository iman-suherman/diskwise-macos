import MaintenanceKit
import XCTest

final class StartupAppsManagerTests: XCTestCase {
    func testAvailableActionsForRecommendedLoginItem() {
        let manager = StartupAppsManager()
        let item = StartupAppItem(
            name: "Steam",
            path: "/Users/test/Library/Application Support/Steam/Steam.AppBundle/Steam.app",
            source: .loginItem,
            isEnabled: true
        )

        XCTAssertEqual(
            manager.availableActions(for: item, recommendation: .disableAtLogin),
            [.removeFromLogin]
        )
        XCTAssertEqual(
            manager.availableActions(for: item, recommendation: .optional),
            [.removeFromLogin]
        )
        XCTAssertTrue(manager.availableActions(for: item, recommendation: .keepAtLogin).isEmpty)
    }

    func testAvailableActionsForBackgroundItem() {
        let manager = StartupAppsManager()
        let item = StartupAppItem(
            name: "Slack",
            path: "/Applications/Slack.app",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            source: .backgroundItem,
            isEnabled: true
        )

        XCTAssertEqual(
            manager.availableActions(for: item, recommendation: .optional),
            [.disableBackgroundActivity]
        )
        XCTAssertTrue(
            manager.availableActions(for: item, recommendation: .keepAtLogin).isEmpty
        )
    }

    func testAvailableActionsForLaunchAgent() {
        let manager = StartupAppsManager()
        let item = StartupAppItem(
            name: "steamclean",
            path: nil,
            bundleIdentifier: "com.valvesoftware.steamclean",
            source: .launchAgent
        )

        XCTAssertEqual(
            manager.availableActions(for: item, recommendation: .disableAtLogin),
            [.unloadLaunchAgent]
        )
    }
}
