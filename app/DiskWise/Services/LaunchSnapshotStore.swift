import Foundation
import DatabaseKit
import AIKit

struct LaunchSnapshotPayload: Codable, Sendable {
    static let currentFormatVersion = 2

    var formatVersion: Int
    let overview: StorageOverview
    let topConsumers: [SpaceConsumer]
    let analysisReport: AnalysisReport?

    init(
        overview: StorageOverview,
        topConsumers: [SpaceConsumer],
        analysisReport: AnalysisReport?
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.overview = overview
        self.topConsumers = topConsumers
        self.analysisReport = analysisReport
    }
}

enum LaunchSnapshotStore {
    static func load(from database: DiskWiseDatabase, diskID: Int64) -> LaunchSnapshotPayload? {
        guard let stored = try? database.loadLaunchSnapshotPayload(forDiskID: diskID),
              stored.formatVersion == LaunchSnapshotPayload.currentFormatVersion,
              let data = stored.payloadJSON.data(using: .utf8),
              let payload = try? JSONDecoder().decode(LaunchSnapshotPayload.self, from: data),
              payload.formatVersion == LaunchSnapshotPayload.currentFormatVersion else {
            return nil
        }
        return payload
    }

    static func save(
        to database: DiskWiseDatabase,
        diskID: Int64,
        overview: StorageOverview,
        topConsumers: [SpaceConsumer],
        analysisReport: AnalysisReport?
    ) {
        let payload = LaunchSnapshotPayload(
            overview: overview,
            topConsumers: topConsumers,
            analysisReport: analysisReport
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return }
        try? database.saveLaunchSnapshotPayload(
            forDiskID: diskID,
            formatVersion: LaunchSnapshotPayload.currentFormatVersion,
            payloadJSON: json
        )
    }
}
