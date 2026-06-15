import Foundation
import MaintenanceKit

public struct StartupAppsAnalysisContext: Sendable {
    public let scanResult: StartupAppsScanResult

    public init(scanResult: StartupAppsScanResult) {
        self.scanResult = scanResult
    }
}

public struct StartupAppsAnalysisReport: Sendable {
    public let scannedAt: Date
    public let items: [StartupAppItem]
    public let analyses: [StartupAppAnalysis]
    public let summary: String?

    public init(
        scannedAt: Date,
        items: [StartupAppItem],
        analyses: [StartupAppAnalysis],
        summary: String? = nil
    ) {
        self.scannedAt = scannedAt
        self.items = items
        self.analyses = analyses
        self.summary = summary
    }

    public func analysis(for item: StartupAppItem) -> StartupAppAnalysis? {
        analyses.first { $0.itemID == item.id }
    }
}
