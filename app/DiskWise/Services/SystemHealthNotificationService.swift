import AIKit
import AppKit
import Foundation
import UserNotifications

@MainActor
final class SystemHealthNotificationService {
    static let shared = SystemHealthNotificationService()

    static let categoryIdentifier = "diskwise.health.poor"
    static let freeMemoryIdentifier = "diskwise.health.freeMemory"
    static let openOptimizationIdentifier = "diskwise.health.openOptimization"

    private let center = UNUserNotificationCenter.current()
    private let cooldown: TimeInterval = 20 * 60
    private var lastNotifiedAt: Date?
    private var lastNotifiedScore: Int?

    private init() {}

    func prepare() {
        let freeMemory = UNNotificationAction(
            identifier: Self.freeMemoryIdentifier,
            title: "Free Memory",
            options: [.foreground]
        )
        let open = UNNotificationAction(
            identifier: Self.openOptimizationIdentifier,
            title: "Open System Optimization",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [freeMemory, open],
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
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func checkSnapshot(_ snapshot: SystemHealthSnapshot?, notificationsEnabled: Bool) async {
        guard notificationsEnabled, let snapshot else {
            if snapshot == nil || (snapshot?.healthScore ?? 100) >= SystemHealthMonitorCore.poorHealthScoreThreshold {
                lastNotifiedAt = nil
                lastNotifiedScore = nil
            }
            return
        }

        if snapshot.healthScore >= SystemHealthMonitorCore.poorHealthScoreThreshold {
            lastNotifiedAt = nil
            lastNotifiedScore = nil
            return
        }

        let now = Date()
        if let lastNotifiedAt, let lastNotifiedScore {
            let elapsed = now.timeIntervalSince(lastNotifiedAt)
            let worsened = snapshot.healthScore <= lastNotifiedScore - 10
            if !worsened, elapsed < cooldown {
                return
            }
        }

        let authorized = await requestAuthorizationIfNeeded()
        guard authorized else { return }

        let suggestions = resolvedSuggestions(for: snapshot)
        let content = UNMutableNotificationContent()
        content.title = "System health is Poor (\(snapshot.healthScore))"
        content.subtitle = "DiskWise · \(Int(snapshot.memoryUsedPercent.rounded()))% memory in use"
        content.body = suggestions.joined(separator: " ")
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "healthScore": snapshot.healthScore,
            "memoryUsedPercent": snapshot.memoryUsedPercent,
        ]

        let request = UNNotificationRequest(
            identifier: "system-health-poor-\(snapshot.healthScore)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            lastNotifiedAt = now
            lastNotifiedScore = snapshot.healthScore
        } catch {
            return
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async -> Bool {
        guard response.notification.request.content.categoryIdentifier == Self.categoryIdentifier else {
            return false
        }

        switch response.actionIdentifier {
        case Self.freeMemoryIdentifier:
            _ = await MemoryActionExecutor.perform(kind: .freeMemory, targetProcessName: nil)
            SystemHealthMonitor.shared.refreshDetailed()
            return true
        case Self.openOptimizationIdentifier, UNNotificationDefaultActionIdentifier:
            AppViewModel.current?.sidebarSelection = .pane(.systemOptimization)
            NSApp.activate(ignoringOtherApps: true)
            return true
        default:
            return false
        }
    }

    private func resolvedSuggestions(for snapshot: SystemHealthSnapshot) -> [String] {
        if let report = MemoryAnalyzerMonitor.shared.report,
           let recommendation = report.recommendations.first(where: {
               $0.actionKind != .informational && $0.priority >= 55
           }) {
            return [recommendation.detail]
        }
        return SystemHealthMonitorCore.poorHealthMemoryCleanupSuggestions(for: snapshot)
    }
}
