import AppKit
import Sparkle

/// Sparkle auto-updates — Debug uses local website (`npm run dev:website`), Release uses production appcast.
final class SparkleUpdaterController: NSObject {
    static let shared = SparkleUpdaterController()

    private let controller: SPUStandardUpdaterController
    private var didCheckOnLaunch = false

    override private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
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

    /// Checks silently on launch — prompts to install only when a newer version exists.
    func checkForUpdatesOnLaunchIfNeeded() {
        guard !didCheckOnLaunch else { return }
        didCheckOnLaunch = true
        updater.checkForUpdatesInBackground()
    }

    private func configureUpdater() {
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = true
        #if DEBUG
        updater.updateCheckInterval = 300
        #else
        updater.updateCheckInterval = 86_400
        #endif
        updater.automaticallyDownloadsUpdates = true
    }
}
