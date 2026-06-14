import AppKit

@MainActor
final class DockScanAnimator {
    static let shared = DockScanAnimator()

    private var view: ScanningDockTileView?

    private init() {}

    func start() {
        guard view == nil else { return }
        guard !AppSettings.shared.hideFromDock else { return }
        guard let image = scanningImage else { return }

        let scanView = ScanningDockTileView(image: image)
        applyProgress(from: ScanActivityMonitor.shared, to: scanView)
        view = scanView
        NSApp.dockTile.contentView = scanView
        NSApp.dockTile.display()
        scanView.startAnimating()
    }

    func updateProgress(fraction: Double, label: String) {
        guard let view else { return }
        view.progressFraction = fraction
        view.progressLabel = label
        view.needsDisplay = true
        NSApp.dockTile.display()
    }

    func stop() {
        view?.stopAnimating()
        view = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    private var scanningImage: NSImage? {
        if let image = NSImage(named: "DockScanning") {
            return image
        }
        if let url = Bundle.main.url(forResource: "scanning", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }

    private func applyProgress(from monitor: ScanActivityMonitor, to view: ScanningDockTileView) {
        view.progressFraction = monitor.progressFraction
        view.progressLabel = monitor.progressPercentLabel
    }
}
