import AppKit
import Sparkle

/// Sparkle auto-updates — Debug uses local website (`npm run dev:website`), Release uses production appcast.
final class SparkleUpdaterController: NSObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdaterController()

    private static let lastForegroundCheckKey = "diskwise.sparkle.lastForegroundUpdateCheck"

    private var controller: SPUStandardUpdaterController!

    override private init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        configureUpdater()
        controller.startUpdater()
    }

    var updater: SPUUpdater {
        controller.updater
    }

    /// Shows Sparkle UI immediately (also reports when already up to date).
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Silent daily check while the app is active and the main window is visible.
    func checkForUpdatesInForegroundIfNeeded() {
        guard NSApp.isActive else { return }
        guard Self.isMainWindowVisible else { return }
        guard shouldRunDailyCheck else { return }

        UserDefaults.standard.set(Date(), forKey: Self.lastForegroundCheckKey)
        updater.checkForUpdatesInBackground()
    }

    private static var isMainWindowVisible: Bool {
        NSApp.windows.contains { $0.canBecomeMain && $0.isVisible }
    }

    private var shouldRunDailyCheck: Bool {
        guard let lastCheck = UserDefaults.standard.object(forKey: Self.lastForegroundCheckKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) >= dailyCheckInterval
    }

    private var dailyCheckInterval: TimeInterval {
        #if DEBUG
        300
        #else
        86_400
        #endif
    }

    private func configureUpdater() {
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = true
    }
}
