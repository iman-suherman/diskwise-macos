import DiskScannerKit
import Foundation

enum NotificationThresholdMode: String, Codable, CaseIterable, Identifiable {
    case percentage
    case absolute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .percentage: return "Percentage"
        case .absolute: return "Free space amount"
        }
    }

    var memoryDescription: String {
        switch self {
        case .percentage: return "Alert when memory used reaches the percentage below."
        case .absolute: return "Alert when free RAM drops below the amount below."
        }
    }

    var diskDescription: String {
        switch self {
        case .percentage: return "Alert when free space drops below the percentage below."
        case .absolute: return "Alert when free space drops below the amount below."
        }
    }
}

struct DiskNotificationVolumeOverride: Codable, Equatable {
    var isEnabled: Bool = true
    var usesCustomThreshold: Bool = false
    var thresholdMode: NotificationThresholdMode = .percentage
    var freePercent: Int = NotificationThresholdDefaults.diskFreePercent
    var freeGigabytes: Double = NotificationThresholdDefaults.diskFreeGigabytes
}

struct DiskNotificationResolvedSettings: Equatable {
    let thresholdMode: NotificationThresholdMode
    let freePercent: Int
    let freeGigabytes: Double
}

enum NotificationThresholdDefaults {
    static let diskFreePercent = 10
    static let diskFreeGigabytes = 100.0
    static let memoryUsedPercent = 85
    static let memoryFreeGigabytes = 4.0

    static let diskFreePercentRange = 1...50
    static let memoryUsedPercentRange = 50...98
    static let diskFreeGigabytesRange = 1.0...1_000.0

    static var physicalMemoryGigabytes: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000
    }

    static var memoryFreeGigabytesRange: ClosedRange<Double> {
        1...max(2, physicalMemoryGigabytes)
    }

    static func defaultMemoryFreeGigabytes() -> Double {
        let suggested = (physicalMemoryGigabytes * 0.15 * 10).rounded() / 10
        return min(max(2, suggested), memoryFreeGigabytesRange.upperBound)
    }

    static func diskFreeGigabytesRange(for totalBytes: Int64) -> ClosedRange<Double> {
        let totalGB = max(1, Double(totalBytes) / 1_000_000_000)
        return 1...min(1_000, totalGB)
    }
}

enum NotificationThresholdLogic {
    static func memoryFreeBytes(from snapshot: SystemHealthSnapshot) -> Int64 {
        max(0, snapshot.physicalMemoryBytes - snapshot.memoryUsedBytes)
    }

    static func isMemoryThresholdExceeded(
        snapshot: SystemHealthSnapshot,
        mode: NotificationThresholdMode,
        usedPercent: Int,
        freeGigabytes: Double
    ) -> Bool {
        switch mode {
        case .percentage:
            return snapshot.memoryUsedPercent >= Double(usedPercent)
        case .absolute:
            let thresholdBytes = Int64((freeGigabytes * 1_000_000_000).rounded())
            return memoryFreeBytes(from: snapshot) < thresholdBytes
        }
    }

    static func isDiskLowOnSpace(
        freeSize: Int64,
        totalSize: Int64,
        settings: DiskNotificationResolvedSettings
    ) -> Bool {
        guard totalSize > 0 else { return false }

        switch settings.thresholdMode {
        case .percentage:
            let freePercent = (Double(freeSize) / Double(totalSize)) * 100
            return freePercent < Double(settings.freePercent)
        case .absolute:
            let thresholdBytes = Int64((settings.freeGigabytes * 1_000_000_000).rounded())
            return freeSize < thresholdBytes
        }
    }

    static func resolvedDiskSettings(
        for volume: MountedVolume,
        globalMode: NotificationThresholdMode,
        globalFreePercent: Int,
        globalFreeGigabytes: Double,
        override: DiskNotificationVolumeOverride?
    ) -> DiskNotificationResolvedSettings? {
        guard volume.totalSize >= DiskSpaceAlertLevel.minimumNotifiableTotalBytes else { return nil }

        if let override, !override.isEnabled {
            return nil
        }

        if let override, override.usesCustomThreshold {
            return DiskNotificationResolvedSettings(
                thresholdMode: override.thresholdMode,
                freePercent: clamp(
                    override.freePercent,
                    to: NotificationThresholdDefaults.diskFreePercentRange
                ),
                freeGigabytes: clamp(
                    override.freeGigabytes,
                    to: NotificationThresholdDefaults.diskFreeGigabytesRange(for: volume.totalSize)
                )
            )
        }

        return DiskNotificationResolvedSettings(
            thresholdMode: globalMode,
            freePercent: globalFreePercent,
            freeGigabytes: globalFreeGigabytes
        )
    }

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
