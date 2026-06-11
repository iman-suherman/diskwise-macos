import AppKit
import Sparkle

/// Sparkle auto-updates — Debug uses local website (`npm run dev:website`), Release uses production appcast.
final class SparkleUpdaterController: NSObject {
    static let shared = SparkleUpdaterController()

    private let controller: SPUStandardUpdaterController

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

    func checkForUpdates() {
        controller.checkForUpdates(nil)
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
