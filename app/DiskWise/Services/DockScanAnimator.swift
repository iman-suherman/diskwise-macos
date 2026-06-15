import AppKit
import DiskScannerKit

@MainActor
final class DockScanAnimator {
    static let shared = DockScanAnimator()

    private var view: ScanningDockTileView?

    private init() {}

    func start() {
        guard ScanActivityMonitor.shared.isScanning else { return }
        guard view == nil else { return }
        guard !AppSettings.shared.hideFromDock else { return }
        guard let layered = ScanningDockTileView.loadLayeredScanningImages() else { return }

        let scanView = ScanningDockTileView(
            baseImage: layered.base,
            ringImage: layered.ring,
            size: NSApp.dockTile.size,
            updatesDockTile: true,
            imageInsetFraction: 0.08
        )
        applyScanState(from: ScanActivityMonitor.shared, to: scanView)
        view = scanView
        NSApp.dockTile.contentView = scanView
        NSApp.dockTile.display()
        scanView.startAnimating()
    }

    func update(from monitor: ScanActivityMonitor) {
        guard let view else { return }
        applyScanState(from: monitor, to: view)
        view.needsDisplay = true
        NSApp.dockTile.display()
    }

    func stop() {
        view?.stopAnimating()
        view = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.display()
    }

    private func applyScanState(from monitor: ScanActivityMonitor, to view: ScanningDockTileView) {
        view.progressFraction = monitor.progressFraction
        view.progressLabel = monitor.progressPercentLabel
        view.statusDescription = Self.statusDescription(from: monitor)
    }

    static func statusDescription(from monitor: ScanActivityMonitor) -> String {
        var parts = ["\(monitor.scanMode.title) scan"]
        if let operationLabel = monitor.operationLabel, !operationLabel.isEmpty {
            parts.append(operationLabel)
        }
        parts.append(monitor.progressPercentLabel)
        return parts.joined(separator: " · ")
    }
}
