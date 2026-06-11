import Foundation

enum ActivityCategory: String, Sendable, CaseIterable {
    case scan
    case duplicate
    case cleanup
    case recommendation
    case system

    var label: String {
        switch self {
        case .scan: return "Scan"
        case .duplicate: return "Duplicates"
        case .cleanup: return "Cleanup"
        case .recommendation: return "Recommendations"
        case .system: return "System"
        }
    }
}

struct ActivityLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let category: ActivityCategory
    let message: String
    let detail: String?

}

@MainActor
final class ActivityLog: ObservableObject {
    static let shared = ActivityLog()

    @Published private(set) var entries: [ActivityLogEntry] = []
    private let maxEntries = 500
    private static let exportFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private init() {
        log(.system, "DiskWise activity log started", detail: appVersionLabel)
    }

    func log(_ category: ActivityCategory, _ message: String, detail: String? = nil) {
        entries.append(
            ActivityLogEntry(
                timestamp: Date(),
                category: category,
                message: message,
                detail: detail
            )
        )
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
        log(.system, "Activity log cleared", detail: appVersionLabel)
    }

    func exportText() -> String {
        var lines = [
            "DiskWise Activity Log",
            "Exported: \(Self.exportFormatter.string(from: Date()))",
            appVersionLabel,
            String(repeating: "-", count: 72),
        ]
        lines.append(contentsOf: entries.map(exportLine(for:)))
        return lines.joined(separator: "\n")
    }

    private func exportLine(for entry: ActivityLogEntry) -> String {
        let time = Self.exportFormatter.string(from: entry.timestamp)
        if let detail = entry.detail, !detail.isEmpty {
            return "[\(time)] [\(entry.category.label)] \(entry.message) — \(detail)"
        }
        return "[\(time)] [\(entry.category.label)] \(entry.message)"
    }

    private var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "Version: \(version) (\(build))"
    }
}
