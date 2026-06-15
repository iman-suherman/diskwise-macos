import AIKit
import AppKit
import DiskScannerKit
import Foundation
import UserNotifications

enum DiskSpaceAlertLevel: Int, Comparable {
    case low

    static func < (lhs: DiskSpaceAlertLevel, rhs: DiskSpaceAlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Ignore tiny mounts (e.g. app DMGs) that are not meaningful storage targets.
    static let minimumNotifiableTotalBytes: Int64 = 512 * 1024 * 1024
    static let lowSpaceFractionThreshold = 0.10
    static let lowSpaceBytesCap: Int64 = 100 * 1_000_000_000

    static func shouldNotify(for volume: MountedVolume) -> Bool {
        volume.totalSize >= minimumNotifiableTotalBytes
    }

    /// Free-space floor for alerts: the lower of 10% of capacity or 100 GB.
    static func lowSpaceFreeBytesThreshold(for totalSize: Int64) -> Int64 {
        let percentThreshold = Int64(Double(totalSize) * lowSpaceFractionThreshold)
        return min(percentThreshold, lowSpaceBytesCap)
    }

    static func isLowOnSpace(freeSize: Int64, totalSize: Int64) -> Bool {
        freeSize < lowSpaceFreeBytesThreshold(for: totalSize)
    }

    static func level(for volume: MountedVolume) -> DiskSpaceAlertLevel? {
        guard shouldNotify(for: volume) else { return nil }
        guard isLowOnSpace(freeSize: volume.freeSize, totalSize: volume.totalSize) else { return nil }
        return .low
    }
}

@MainActor
final class DiskSpaceNotificationService {
    static let shared = DiskSpaceNotificationService()

    static let categoryIdentifier = "diskwise.disk.lowSpace"
    static let openDiskAnalysisIdentifier = "diskwise.disk.openAnalysis"

    private let center = UNUserNotificationCenter.current()
    private let cooldown: TimeInterval = 30 * 60
    private var lastNotifiedLevel: [String: DiskSpaceAlertLevel] = [:]
    private var lastNotifiedAt: [String: Date] = [:]

    private init() {}

    func prepare() {
        let open = UNNotificationAction(
            identifier: Self.openDiskAnalysisIdentifier,
            title: "Open Disk Analysis",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        center.getNotificationCategories { existing in
            var categories = existing
            categories.insert(category)
            self.center.setNotificationCategories(categories)
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func checkVolumes(_ volumes: [MountedVolume], notificationsEnabled: Bool) async {
        guard notificationsEnabled else {
            lastNotifiedLevel.removeAll()
            lastNotifiedAt.removeAll()
            return
        }

        let availablePaths = Set(volumes.map(\.mountPath))
        lastNotifiedLevel = lastNotifiedLevel.filter { availablePaths.contains($0.key) }
        lastNotifiedAt = lastNotifiedAt.filter { availablePaths.contains($0.key) }

        for volume in volumes {
            await checkVolume(volume)
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        guard response.notification.request.content.categoryIdentifier == Self.categoryIdentifier else {
            return false
        }

        switch response.actionIdentifier {
        case Self.openDiskAnalysisIdentifier, UNNotificationDefaultActionIdentifier:
            AppViewModel.current?.sidebarSelection = .pane(.overview)
            NSApp.activate(ignoringOtherApps: true)
            return true
        default:
            return false
        }
    }

    private func checkVolume(_ volume: MountedVolume) async {
        guard let level = DiskSpaceAlertLevel.level(for: volume) else {
            lastNotifiedLevel.removeValue(forKey: volume.mountPath)
            lastNotifiedAt.removeValue(forKey: volume.mountPath)
            return
        }

        let previousLevel = lastNotifiedLevel[volume.mountPath]
        let previousAt = lastNotifiedAt[volume.mountPath]
        let now = Date()

        if let previousLevel, let previousAt {
            if level <= previousLevel,
               now.timeIntervalSince(previousAt) < cooldown {
                return
            }
        }

        let authorized = await requestAuthorizationIfNeeded()
        guard authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: volume)
        content.subtitle = "DiskWise · \(volume.name)"
        content.body = notificationBody(for: volume)
        content.interruptionLevel = .active
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "mountPath": volume.mountPath,
            "alertLevel": "low",
        ]

        let request = UNNotificationRequest(
            identifier: "disk-space-\(volume.mountPath)-low",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            lastNotifiedLevel[volume.mountPath] = level
            lastNotifiedAt[volume.mountPath] = now
        } catch {
            return
        }
    }

    private func notificationTitle(for volume: MountedVolume) -> String {
        "\(volume.name) is running low on space"
    }

    private func notificationBody(for volume: MountedVolume) -> String {
        let freeBytes = MenuBarFormatters.resolvedFreeBytes(for: volume)
        let freeLabel = MenuBarFormatters.readableFreeSpace(freeBytes)
        let freePercent = Int((max(0, 1 - volume.usageFraction) * 100).rounded())
        return "Only \(freeLabel) free (\(freePercent)% remaining). Review large files and safe cleanup options."
    }
}
