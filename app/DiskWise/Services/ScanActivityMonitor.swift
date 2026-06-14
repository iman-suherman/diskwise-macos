import DiskScannerKit
import Foundation

@MainActor
final class ScanActivityMonitor: ObservableObject {
    static let shared = ScanActivityMonitor()

    @Published private(set) var isScanning = false
    @Published private(set) var volumeName: String?
    @Published private(set) var progressFraction: Double = 0
    @Published private(set) var progressPercentLabel = "0%"
    @Published private(set) var detail: String?
    @Published private(set) var operationLabel: String?
    @Published private(set) var scanMode: ScanMode = .fast

    private init() {}

    func beginScan(volumeName: String, mode: ScanMode = .fast) {
        isScanning = true
        self.volumeName = volumeName
        scanMode = mode
        progressFraction = 0.08
        progressPercentLabel = "0%"
        detail = nil
        operationLabel = nil
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
    }

    func endScan() {
        isScanning = false
        volumeName = nil
        scanMode = .fast
        progressFraction = 0
        progressPercentLabel = "0%"
        detail = nil
        operationLabel = nil
    }
}
