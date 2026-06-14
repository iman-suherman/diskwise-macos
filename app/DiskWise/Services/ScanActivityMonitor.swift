import DiskScannerKit
import Foundation

@MainActor
final class ScanActivityMonitor: ObservableObject {
    static let shared = ScanActivityMonitor()

    @Published private(set) var isScanning = false
    @Published private(set) var volumeName: String?
    @Published private(set) var volumeMountPath: String?
    @Published private(set) var progressFraction: Double = 0
    @Published private(set) var progressPercentLabel = "0%"
    @Published private(set) var detail: String?
    @Published private(set) var operationLabel: String?
    @Published private(set) var scanMode: ScanMode = .fast

    private init() {}

    func beginScan(volumeName: String, volumeMountPath: String, mode: ScanMode = .fast) {
        isScanning = true
        self.volumeName = volumeName
        self.volumeMountPath = volumeMountPath
        scanMode = mode
        progressFraction = 0.08
        progressPercentLabel = "0%"
        detail = nil
        operationLabel = nil
        DockScanAnimator.shared.start()
    }

    func update(
        progressFraction: Double,
        progressPercentLabel: String,
        detail: String?,
        operationLabel: String?
    ) {
        isScanning = true
        self.progressFraction = progressFraction
        self.progressPercentLabel = progressPercentLabel
        self.detail = detail
        self.operationLabel = operationLabel
        DockScanAnimator.shared.update(from: self)
    }

    func isScanningVolume(_ mountPath: String) -> Bool {
        isScanning && volumeMountPath == mountPath
    }

    func endScan() {
        isScanning = false
        volumeName = nil
        volumeMountPath = nil
        scanMode = .fast
        progressFraction = 0
        progressPercentLabel = "0%"
        detail = nil
        operationLabel = nil
        DockScanAnimator.shared.stop()
    }
}
