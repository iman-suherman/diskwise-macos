import AIKit
import AppKit
import DatabaseKit
import DiskScannerKit
import Foundation
import UserNotifications

@MainActor
final class ScanCleanupNotificationService {
    static let shared = ScanCleanupNotificationService()

    static let performCleanupIdentifier = "diskwise.scan.performCleanup"
    static let openBreakdownIdentifier = "diskwise.scan.openBreakdown"

    private let center = UNUserNotificationCenter.current()
    private var registeredCategoryIDs: Set<String> = []

    private init() {}

    func prepare() {
        registerCategory(for: "thin_apfs_snapshots", actionTitle: "Thin Snapshots")
        registerCategory(for: "delete_cache", actionTitle: "Move to Trash")
        registerCategory(for: "delete_logs", actionTitle: "Move to Trash")
        registerCategory(for: "delete_previews", actionTitle: "Move to Trash")
        registerCategory(for: "project_purge", actionTitle: "Move to Trash")
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

    func notifyAfterScan(
        report: AnalysisReport,
        volumeName: String,
        scanMode: ScanMode,
        diskID: Int64,
        volumeMountPath: String,
        notificationsEnabled: Bool
    ) async {
        guard notificationsEnabled else { return }

        let safeItems = report.recommendations.filter { recommendation in
            ActionBucket.bucket(for: recommendation) == .safeRegenerable
                && (recommendation.estimatedSavings > 0 || recommendation.type == "thin_apfs_snapshots")
        }
        guard !safeItems.isEmpty else { return }

        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return }

        let stamp = Int(Date().timeIntervalSince1970)
        for (index, recommendation) in safeItems.enumerated() {
            await notify(
                for: recommendation,
                volumeName: volumeName,
                scanMode: scanMode,
                diskID: diskID,
                volumeMountPath: volumeMountPath,
                identifierSuffix: "\(stamp)-\(index)"
            )
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async -> Bool {
        let categoryID = response.notification.request.content.categoryIdentifier
        guard categoryID.hasPrefix("diskwise.scan.cleanup.") else {
            return false
        }

        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case Self.performCleanupIdentifier:
            guard let recommendationType = userInfo["recommendationType"] as? String,
                  let title = userInfo["title"] as? String else {
                return false
            }
            let diskID = Self.diskID(from: userInfo)
            guard let diskID else { return false }

            await AppViewModel.current?.performSafeCleanupFromNotification(
                recommendationType: recommendationType,
                title: title,
                diskID: diskID
            )
            return true
        case Self.openBreakdownIdentifier, UNNotificationDefaultActionIdentifier:
            AppViewModel.current?.openResultsTab()
            NSApp.activate(ignoringOtherApps: true)
            return true
        default:
            return false
        }
    }

    private func notify(
        for recommendation: RecommendationRecord,
        volumeName: String,
        scanMode: ScanMode,
        diskID: Int64,
        volumeMountPath: String,
        identifierSuffix: String
    ) async {
        let actionTitle = actionTitle(for: recommendation.type)
        registerCategory(for: recommendation.type, actionTitle: actionTitle)

        let content = UNMutableNotificationContent()
        content.title = recommendation.title
        content.subtitle = "\(scanMode.title) scan complete · \(volumeName) · Safe to Clean"
        content.body = notificationBody(for: recommendation)
        content.interruptionLevel = .active
        content.categoryIdentifier = categoryIdentifier(for: recommendation.type)
        content.userInfo = [
            "recommendationType": recommendation.type,
            "title": recommendation.title,
            "diskID": diskID,
            "volumeMountPath": volumeMountPath,
        ]

        let request = UNNotificationRequest(
            identifier: "scan-cleanup-\(recommendation.type)-\(identifierSuffix)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            return
        }
    }

    private func categoryIdentifier(for recommendationType: String) -> String {
        "diskwise.scan.cleanup.\(recommendationType)"
    }

    private func registerCategory(for recommendationType: String, actionTitle: String) {
        let identifier = categoryIdentifier(for: recommendationType)
        guard !registeredCategoryIDs.contains(identifier) else { return }
        registeredCategoryIDs.insert(identifier)

        let cleanup = UNNotificationAction(
            identifier: Self.performCleanupIdentifier,
            title: actionTitle,
            options: [.foreground]
        )
        let open = UNNotificationAction(
            identifier: Self.openBreakdownIdentifier,
            title: "Review in DiskWise",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: [cleanup, open],
            intentIdentifiers: [],
            options: []
        )
        center.getNotificationCategories { existing in
            var categories = existing
            categories.insert(category)
            self.center.setNotificationCategories(categories)
        }
    }

    private func actionTitle(for recommendationType: String) -> String {
        switch recommendationType {
        case "thin_apfs_snapshots":
            return "Thin Snapshots"
        default:
            return "Move to Trash"
        }
    }

    private func notificationBody(for recommendation: RecommendationRecord) -> String {
        var parts: [String] = []
        if recommendation.estimatedSavings > 0 {
            parts.append(
                "Save about \(ByteCountFormatter.string(fromByteCount: recommendation.estimatedSavings, countStyle: .file))"
            )
        }
        let reason = recommendation.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty {
            parts.append(reason)
        }
        let body = parts.joined(separator: " — ")
        if body.count <= 200 {
            return body
        }
        return String(body.prefix(197)) + "…"
    }

    private static func diskID(from userInfo: [AnyHashable: Any]) -> Int64? {
        if let value = userInfo["diskID"] as? Int64 {
            return value
        }
        if let value = userInfo["diskID"] as? Int {
            return Int64(value)
        }
        if let value = userInfo["diskID"] as? NSNumber {
            return value.int64Value
        }
        return nil
    }
}
