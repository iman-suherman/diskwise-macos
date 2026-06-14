import Foundation

public enum MemoryIssueHistory {
    public static func issueKey(for recommendation: MemoryActionRecommendation) -> String {
        let target = normalizedTarget(for: recommendation.targetProcessName)
        if target.isEmpty {
            return recommendation.actionKind.rawValue
        }
        return "\(recommendation.actionKind.rawValue)|\(target)"
    }

    public static func displayTitle(for recommendation: MemoryActionRecommendation) -> String {
        if let target = recommendation.targetProcessName, !target.isEmpty {
            let friendly = MemoryProcessRules.userFacingApplicationName(for: target)
            if !friendly.isEmpty {
                switch recommendation.actionKind {
                case .quitProcess:
                    return "Quit \(friendly)"
                case .restartApp:
                    return "Restart \(friendly)"
                case .reduceTabs:
                    return "Focus \(friendly)"
                case .freeMemory:
                    return "Free inactive memory"
                case .informational:
                    break
                }
            }
        }
        return recommendation.title
    }

    public static func normalizedTarget(for name: String?) -> String {
        guard let name, !name.isEmpty else { return "" }
        return MemoryProcessRules.userFacingApplicationName(for: name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

public struct MemoryIssueOccurrenceRecord: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let memoryUsedPercent: Double

    public init(timestamp: Date, memoryUsedPercent: Double) {
        self.timestamp = timestamp
        self.memoryUsedPercent = memoryUsedPercent
    }
}

public struct MemoryIssuePatternRecord: Sendable, Codable, Equatable, Identifiable {
    public var issueKey: String
    public var displayTitle: String
    public var actionKind: MemoryActionKind
    public var targetProcessName: String?
    public var occurrences: [MemoryIssueOccurrenceRecord]
    public var suppressedNotificationCount: Int
    public var lastNotifiedAt: Date?
    public var notificationCount: Int

    public var id: String { issueKey }

    public init(
        issueKey: String,
        displayTitle: String,
        actionKind: MemoryActionKind,
        targetProcessName: String?,
        occurrences: [MemoryIssueOccurrenceRecord] = [],
        suppressedNotificationCount: Int = 0,
        lastNotifiedAt: Date? = nil,
        notificationCount: Int = 0
    ) {
        self.issueKey = issueKey
        self.displayTitle = displayTitle
        self.actionKind = actionKind
        self.targetProcessName = targetProcessName
        self.occurrences = occurrences
        self.suppressedNotificationCount = suppressedNotificationCount
        self.lastNotifiedAt = lastNotifiedAt
        self.notificationCount = notificationCount
    }
}

public struct MemoryIssuePatternSummary: Sendable, Identifiable, Equatable {
    public let issueKey: String
    public let displayTitle: String
    public let actionKind: MemoryActionKind
    public let targetProcessName: String?
    public let occurrenceCount: Int
    public let suppressedNotificationCount: Int
    public let notificationCount: Int
    public let firstSeenAt: Date
    public let lastSeenAt: Date
    public let lastNotifiedAt: Date?
    public let averageInterval: TimeInterval?
    public let medianInterval: TimeInterval?
    public let typicalMemoryUsedPercent: Double

    public var id: String { issueKey }
}

public enum MemoryIssuePatternAnalyzer {
    public static let defaultRepeatNotificationInterval: TimeInterval = 4 * 60 * 60
    public static let defaultMinimumOccurrenceGap: TimeInterval = 30 * 60

    public static func summarize(_ records: [MemoryIssuePatternRecord]) -> [MemoryIssuePatternSummary] {
        records
            .map { summarize($0) }
            .sorted { lhs, rhs in
                if lhs.occurrenceCount != rhs.occurrenceCount {
                    return lhs.occurrenceCount > rhs.occurrenceCount
                }
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
    }

    public static func summarize(_ record: MemoryIssuePatternRecord) -> MemoryIssuePatternSummary {
        let timestamps = record.occurrences.map(\.timestamp).sorted()
        let intervals = zip(timestamps.dropFirst(), timestamps).map { later, earlier in
            later.timeIntervalSince(earlier)
        }
        let averageInterval = intervals.isEmpty ? nil : intervals.reduce(0, +) / Double(intervals.count)
        let medianInterval = intervals.isEmpty ? nil : median(of: intervals)
        let memoryPercents = record.occurrences.map(\.memoryUsedPercent)
        let typicalMemory = memoryPercents.isEmpty ? 0 : memoryPercents.reduce(0, +) / Double(memoryPercents.count)

        return MemoryIssuePatternSummary(
            issueKey: record.issueKey,
            displayTitle: record.displayTitle,
            actionKind: record.actionKind,
            targetProcessName: record.targetProcessName,
            occurrenceCount: record.occurrences.count,
            suppressedNotificationCount: record.suppressedNotificationCount,
            notificationCount: record.notificationCount,
            firstSeenAt: timestamps.first ?? Date(),
            lastSeenAt: timestamps.last ?? Date(),
            lastNotifiedAt: record.lastNotifiedAt,
            averageInterval: averageInterval,
            medianInterval: medianInterval,
            typicalMemoryUsedPercent: typicalMemory
        )
    }

    public static func shouldNotify(
        lastNotifiedAt: Date?,
        now: Date,
        repeatInterval: TimeInterval = defaultRepeatNotificationInterval
    ) -> Bool {
        guard let lastNotifiedAt else { return true }
        return now.timeIntervalSince(lastNotifiedAt) >= repeatInterval
    }

    public static func shouldRecordOccurrence(
        lastSeenAt: Date?,
        now: Date,
        minimumGap: TimeInterval = defaultMinimumOccurrenceGap
    ) -> Bool {
        guard let lastSeenAt else { return true }
        return now.timeIntervalSince(lastSeenAt) >= minimumGap
    }

    public static func formatInterval(_ interval: TimeInterval?) -> String {
        guard let interval, interval > 0 else { return "—" }
        if interval < 60 {
            return "\(Int(interval.rounded()))s"
        }
        if interval < 3_600 {
            return "\(Int((interval / 60).rounded()))m"
        }
        if interval < 86_400 {
            return String(format: "%.1fh", interval / 3_600)
        }
        return String(format: "%.1fd", interval / 86_400)
    }

    private static func median(of values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
