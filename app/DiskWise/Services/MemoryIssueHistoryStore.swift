import AIKit
import Foundation

@MainActor
final class MemoryIssueHistoryStore: ObservableObject {
    static let shared = MemoryIssueHistoryStore()

    struct RegistrationOutcome: Sendable {
        let issueKey: String
        let shouldNotify: Bool
        let occurrenceRecorded: Bool
    }

    @Published private(set) var patterns: [MemoryIssuePatternSummary] = []

    private let storageKey = "diskwise.memoryIssueHistory.v1"
    private let repeatNotificationInterval = MemoryIssuePatternAnalyzer.defaultRepeatNotificationInterval
    private let minimumOccurrenceGap = MemoryIssuePatternAnalyzer.defaultMinimumOccurrenceGap
    private let maxOccurrencesPerIssue = 50
    private let maxIssues = 30

    private var records: [MemoryIssuePatternRecord] = []

    private init() {
        load()
        refreshSummaries()
    }

    func registerOccurrence(
        report: MemoryAnalysisReport,
        recommendation: MemoryActionRecommendation,
        now: Date = Date()
    ) -> RegistrationOutcome {
        let issueKey = MemoryIssueHistory.issueKey(for: recommendation)
        let index = records.firstIndex { $0.issueKey == issueKey }

        var occurrenceRecorded = false
        if let index {
            let lastSeen = records[index].occurrences.last?.timestamp
            if MemoryIssuePatternAnalyzer.shouldRecordOccurrence(
                lastSeenAt: lastSeen,
                now: now,
                minimumGap: minimumOccurrenceGap
            ) {
                appendOccurrence(
                    at: index,
                    timestamp: now,
                    memoryUsedPercent: report.currentUsedPercent
                )
                occurrenceRecorded = true
            }
            records[index].displayTitle = MemoryIssueHistory.displayTitle(for: recommendation)
        } else {
            let record = MemoryIssuePatternRecord(
                issueKey: issueKey,
                displayTitle: MemoryIssueHistory.displayTitle(for: recommendation),
                actionKind: recommendation.actionKind,
                targetProcessName: recommendation.targetProcessName,
                occurrences: [
                    MemoryIssueOccurrenceRecord(
                        timestamp: now,
                        memoryUsedPercent: report.currentUsedPercent
                    ),
                ]
            )
            records.append(record)
            occurrenceRecorded = true
        }

        trimRecordsIfNeeded()
        persist()
        refreshSummaries()

        let lastNotified = records.first { $0.issueKey == issueKey }?.lastNotifiedAt
        let shouldNotify = MemoryIssuePatternAnalyzer.shouldNotify(
            lastNotifiedAt: lastNotified,
            now: now,
            repeatInterval: repeatNotificationInterval
        )

        return RegistrationOutcome(
            issueKey: issueKey,
            shouldNotify: shouldNotify,
            occurrenceRecorded: occurrenceRecorded
        )
    }

    func markNotified(issueKey: String, at date: Date = Date()) {
        guard let index = records.firstIndex(where: { $0.issueKey == issueKey }) else { return }
        records[index].lastNotifiedAt = date
        records[index].notificationCount += 1
        persist()
        refreshSummaries()
    }

    func recordSuppressedNotification(issueKey: String) {
        guard let index = records.firstIndex(where: { $0.issueKey == issueKey }) else { return }
        records[index].suppressedNotificationCount += 1
        persist()
        refreshSummaries()
    }

    private func appendOccurrence(at index: Int, timestamp: Date, memoryUsedPercent: Double) {
        records[index].occurrences.append(
            MemoryIssueOccurrenceRecord(timestamp: timestamp, memoryUsedPercent: memoryUsedPercent)
        )
        if records[index].occurrences.count > maxOccurrencesPerIssue {
            records[index].occurrences.removeFirst(
                records[index].occurrences.count - maxOccurrencesPerIssue
            )
        }
    }

    private func trimRecordsIfNeeded() {
        guard records.count > maxIssues else { return }
        records.sort { lhs, rhs in
            let lhsDate = lhs.occurrences.last?.timestamp ?? .distantPast
            let rhsDate = rhs.occurrences.last?.timestamp ?? .distantPast
            return lhsDate > rhsDate
        }
        records = Array(records.prefix(maxIssues))
    }

    private func refreshSummaries() {
        patterns = MemoryIssuePatternAnalyzer.summarize(records)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            records = try JSONDecoder().decode([MemoryIssuePatternRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
