import Foundation
import DatabaseKit

/// Risk tier for cleanup recommendations — mirrors a storage consultant's triage buckets.
public enum ActionBucket: String, Sendable, CaseIterable, Identifiable {
    case safeRegenerable
    case reviewFirst
    case personalKeep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .safeRegenerable: return "Safe to Clean"
        case .reviewFirst: return "Review First"
        case .personalKeep: return "Personal — Keep"
        }
    }

    public var subtitle: String {
        switch self {
        case .safeRegenerable:
            return "Caches, logs, and regenerable artifacts — delete freely"
        case .reviewFirst:
            return "Large or important data — verify before removing"
        case .personalKeep:
            return "Photos, media libraries, and personal files — review only"
        }
    }

    public var icon: String {
        switch self {
        case .safeRegenerable: return "checkmark.seal.fill"
        case .reviewFirst: return "exclamationmark.triangle.fill"
        case .personalKeep: return "heart.fill"
        }
    }

    public var tintName: String {
        switch self {
        case .safeRegenerable: return "green"
        case .reviewFirst: return "orange"
        case .personalKeep: return "blue"
        }
    }

    public static func bucket(forRecommendationType type: String) -> ActionBucket {
        switch type {
        case "delete_cache", "delete_previews", "delete_logs", "project_purge",
             "thin_apfs_snapshots", "maintenance_app_caches", "maintenance_browser_caches",
             "maintenance_developer_caches", "maintenance_logs", "maintenance_temp",
             "maintenance_node_modules", "maintenance_build_artifacts", "maintenance_virtual_env":
            return .safeRegenerable
        case "delete_dmg", "delete_ios_backups", "clean_downloads", "duplicate_cleanup":
            return .reviewFirst
        case "archive_old_files":
            return .personalKeep
        default:
            return .reviewFirst
        }
    }

    public static func bucket(for recommendation: RecommendationRecord) -> ActionBucket {
        bucket(forRecommendationType: recommendation.type)
    }

    public var selectsFilesByDefault: Bool {
        switch self {
        case .safeRegenerable: return true
        case .reviewFirst, .personalKeep: return false
        }
    }
}

public extension AnalysisReport {
    var recommendationsByBucket: [ActionBucket: [RecommendationRecord]] {
        Dictionary(grouping: recommendations, by: { ActionBucket.bucket(for: $0) })
    }

    func savings(for bucket: ActionBucket) -> Int64 {
        recommendationsByBucket[bucket, default: []].reduce(0) { $0 + $1.estimatedSavings }
    }
}
