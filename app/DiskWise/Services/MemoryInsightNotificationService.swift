import AIKit
import AppKit
import Foundation
import UserNotifications

@MainActor
final class MemoryInsightNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MemoryInsightNotificationService()

    static let performActionIdentifier = "diskwise.memory.perform"
    static let openAnalyzerIdentifier = "diskwise.memory.open"

    private let center = UNUserNotificationCenter.current()
    private var registeredCategoryIDs: Set<String> = []

    private override init() {
        super.init()
        center.delegate = self
    }

    func prepare() {
        registerCategory(for: .freeMemory, title: "Free Memory")
        registerCategory(for: .quitProcess, title: "Quit App")
        registerCategory(for: .restartApp, title: "Restart App")
        registerCategory(for: .reduceTabs, title: "Focus App")
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

    func notify(
        for report: MemoryAnalysisReport,
        recommendation: MemoryActionRecommendation,
        issueKey: String
    ) async -> Bool {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return false }

        let actionTitle = MemoryActionExecutor.actionTitle(for: recommendation) ?? "Perform Action"
        registerCategory(for: recommendation.actionKind, title: actionTitle)

        let content = UNMutableNotificationContent()
        content.title = recommendation.title
        content.subtitle = "Memory Analyzer · \(Int(report.currentUsedPercent.rounded()))% in use"
        content.body = notificationBody(for: report, recommendation: recommendation)
        content.interruptionLevel = .active
        content.categoryIdentifier = categoryIdentifier(for: recommendation.actionKind)
        content.userInfo = [
            "recommendationID": recommendation.id.uuidString,
            "actionKind": recommendation.actionKind.rawValue,
            "targetProcessName": recommendation.targetProcessName ?? "",
            "title": recommendation.title,
            "issueKey": issueKey,
        ]

        let request = UNNotificationRequest(
            identifier: "memory-insight-\(issueKey)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async -> Bool {
        if DiskSpaceNotificationService.shared.handleNotificationResponse(response) {
            return true
        }
        if await SystemHealthNotificationService.shared.handleNotificationResponse(response) {
            return true
        }
        if await ScanCleanupNotificationService.shared.handleNotificationResponse(response) {
            return true
        }

        let userInfo = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case Self.performActionIdentifier:
            guard let kindRaw = userInfo["actionKind"] as? String,
                  let kind = MemoryActionKind(rawValue: kindRaw) else {
                return false
            }
            let target = (userInfo["targetProcessName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            _ = await MemoryActionExecutor.perform(kind: kind, targetProcessName: target)
            MemoryAnalyzerMonitor.shared.captureNow()
            return true
        case Self.openAnalyzerIdentifier, UNNotificationDefaultActionIdentifier:
            AppViewModel.current?.openMemoryAnalyzerSuggestedActions()
            return true
        default:
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MemoryInsightNotificationService.shared.handleNotificationResponse(response)
    }

    private func categoryIdentifier(for kind: MemoryActionKind) -> String {
        "diskwise.memory.\(kind.rawValue)"
    }

    private func registerCategory(for kind: MemoryActionKind, title: String) {
        let identifier = categoryIdentifier(for: kind)
        guard !registeredCategoryIDs.contains(identifier) else { return }
        registeredCategoryIDs.insert(identifier)

        let perform = UNNotificationAction(
            identifier: Self.performActionIdentifier,
            title: title,
            options: [.foreground]
        )
        let open = UNNotificationAction(
            identifier: Self.openAnalyzerIdentifier,
            title: "Review Suggested Actions",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: [perform, open],
            intentIdentifiers: [],
            options: []
        )
        center.getNotificationCategories { existing in
            var categories = existing
            categories.insert(category)
            self.center.setNotificationCategories(categories)
        }
    }

    private func notificationBody(
        for report: MemoryAnalysisReport,
        recommendation: MemoryActionRecommendation
    ) -> String {
        if let summary = report.aiSummary?
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            let firstParagraph = summary
                .components(separatedBy: "\n\n")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? summary
            if firstParagraph.count <= 180 {
                return firstParagraph
            }
            return String(firstParagraph.prefix(177)) + "…"
        }
        return recommendation.detail
    }
}
