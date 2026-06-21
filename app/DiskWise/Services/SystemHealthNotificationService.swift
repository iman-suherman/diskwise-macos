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
    private var lastNotifiedMemoryUsedPercent: Double?

    private init() {}

    func prepare() {
        let freeMemory = UNNotificationAction(
            identifier: Self.freeMemoryIdentifier,
            title: "Free Memory",
            options: [.foreground]
        )
        let open = UNNotificationAction(
            identifier: Self.openOptimizationIdentifier,
            title: "Review Suggested Actions",
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
                return try await center.requestAuthorization(options: [.alert, .badge])
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    func checkSnapshot(
        _ snapshot: SystemHealthSnapshot?,
        notificationsEnabled: Bool,
        settings: AppSettings = .shared
    ) async {
        guard notificationsEnabled, let snapshot else {
            lastNotifiedAt = nil
            lastNotifiedMemoryUsedPercent = nil
            return
        }

        let thresholdExceeded = NotificationThresholdLogic.isMemoryThresholdExceeded(
            snapshot: snapshot,
            mode: settings.memoryNotificationThresholdMode,
            usedPercent: settings.memoryNotificationUsedPercent,
            freeGigabytes: settings.memoryNotificationFreeGigabytes
        )
        let pressureCritical = NotificationThresholdLogic.isMemoryPressureCritical(snapshot: snapshot)

        guard thresholdExceeded || pressureCritical else {
            lastNotifiedAt = nil
            lastNotifiedMemoryUsedPercent = nil
            return
        }

        let now = Date()
        if let lastNotifiedAt, let lastNotifiedMemoryUsedPercent {
            let elapsed = now.timeIntervalSince(lastNotifiedAt)
            let worsened = snapshot.memoryUsedPercent >= lastNotifiedMemoryUsedPercent + 5
            if !worsened, elapsed < cooldown {
                return
            }
        }

        let authorized = await requestAuthorizationIfNeeded()
        guard authorized else { return }

        let suggestions = resolvedSuggestions(for: snapshot)
        let assessment = snapshot.memoryPressureAssessment
        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: snapshot, settings: settings, assessment: assessment)
        content.subtitle = "DiskWise · \(assessment.severity.label) memory pressure"
        content.body = suggestions.joined(separator: " ")
        content.interruptionLevel = .active
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            "memoryUsedPercent": snapshot.memoryUsedPercent,
        ]

        let request = UNNotificationRequest(
            identifier: "system-health-memory-\(Int(snapshot.memoryUsedPercent.rounded()))",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            lastNotifiedAt = now
            lastNotifiedMemoryUsedPercent = snapshot.memoryUsedPercent
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
            AppViewModel.current?.openMemoryAnalyzerSuggestedActions()
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

    private func notificationTitle(
        for snapshot: SystemHealthSnapshot,
        settings: AppSettings,
        assessment: MemoryPressureAssessment
    ) -> String {
        if assessment.reliefTier == .reboot {
            return "Restart recommended — swap is \(MenuBarFormatters.gigabytes(assessment.metrics.swapUsedBytes))"
        }
        if let target = assessment.recommendedQuitTarget, assessment.reliefTier == .quitApps {
            return "Quit \(target.name) to free memory"
        }
        switch settings.memoryNotificationThresholdMode {
        case .percentage:
            return "Memory pressure is \(assessment.severity.label) (\(Int(snapshot.memoryUsedPercent.rounded()))% in use)"
        case .absolute:
            let freeBytes = NotificationThresholdLogic.memoryFreeBytes(from: snapshot)
            let freeLabel = MenuBarFormatters.readableFreeSpace(freeBytes)
            return "Free RAM is low (\(freeLabel) remaining)"
        }
    }
}
