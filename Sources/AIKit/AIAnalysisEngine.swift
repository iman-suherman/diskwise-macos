import Foundation
import DatabaseKit

public struct StorageInsight: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let detail: String
    public let estimatedSavings: Int64

    public init(title: String, detail: String, estimatedSavings: Int64) {
        self.title = title
        self.detail = detail
        self.estimatedSavings = estimatedSavings
    }
}

public struct AnalysisReport: Sendable {
    public let overview: StorageOverview
    public let insights: [StorageInsight]
    public let recommendations: [RecommendationRecord]
    public let potentialReclaimableSpace: Int64

    public init(
        overview: StorageOverview,
        insights: [StorageInsight],
        recommendations: [RecommendationRecord],
        potentialReclaimableSpace: Int64
    ) {
        self.overview = overview
        self.insights = insights
        self.recommendations = recommendations
        self.potentialReclaimableSpace = potentialReclaimableSpace
    }
}

public struct OllamaConfiguration: Sendable {
    public let baseURL: URL
    public let model: String

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, model: String = "llama3.1") {
        self.baseURL = baseURL
        self.model = model
    }
}

public final class AIAnalysisEngine: @unchecked Sendable {
    private let database: DiskWiseDatabase
    private let ollamaConfiguration: OllamaConfiguration?

    public init(database: DiskWiseDatabase, ollamaConfiguration: OllamaConfiguration? = nil) {
        self.database = database
        self.ollamaConfiguration = ollamaConfiguration
    }

    public func analyze(diskID: Int64, fileLimit: Int = 10_000) throws -> AnalysisReport {
        let oldThreshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        let overview = try database.storageOverview(forDiskID: diskID, oldFileThreshold: oldThreshold)
        let duplicateGroups = try database.duplicateGroups(forDiskID: diskID, limit: 50)
        let cappedLimit = max(500, min(fileLimit, 500_000))
        let allFiles = try database.files(forDiskID: diskID, limit: cappedLimit)

        let previewLikeFiles = allFiles.filter { file in
            let name = URL(fileURLWithPath: file.path).lastPathComponent.lowercased()
            return name.contains("preview") || name.contains("thumb") || name.contains(".tmp")
        }

        let cacheBytes = try database.categorySize(forDiskID: diskID, category: .cache)
        let dmgBytes = allFiles
            .filter { RemovablePathRules.isUserManagedInstallerArtifact($0.path) }
            .reduce(Int64(0)) { $0 + $1.size }
        let downloadBytes = try database.categorySize(forDiskID: diskID, category: .downloads)
        let iosBackupBytes = allFiles
            .filter { file in
                let lower = file.path.lowercased()
                return lower.contains("mobilesync/backup") || lower.contains("/ios backup")
            }
            .reduce(Int64(0)) { $0 + $1.size }
        let tempExportBytes = allFiles
            .filter { $0.category == .temporary }
            .reduce(Int64(0)) { $0 + $1.size }
        let oldVideoBytes = allFiles
            .filter { file in
                guard VideoFileRules.isArchivableOldVideo(file.path) else { return false }
                if let accessed = file.lastAccessed, accessed < oldThreshold { return true }
                if file.lastAccessed == nil, let modified = file.modifiedAt, modified < oldThreshold {
                    return true
                }
                return false
            }
            .reduce(Int64(0)) { $0 + $1.size }

        var insights: [StorageInsight] = []
        var recommendations: [RecommendationRecord] = []

        if overview.duplicateSavings > 0 {
            insights.append(
                StorageInsight(
                    title: "Duplicate files",
                    detail: "\(duplicateGroups.count) duplicate groups found.",
                    estimatedSavings: overview.duplicateSavings
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "duplicate_cleanup",
                    title: "Clean Duplicates",
                    estimatedSavings: overview.duplicateSavings,
                    reason: "Multiple files share identical or near-identical content."
                )
            )
        }

        if cacheBytes > 0 {
            insights.append(
                StorageInsight(
                    title: "Cache files",
                    detail: "Application and system cache data.",
                    estimatedSavings: cacheBytes
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "delete_cache",
                    title: "Delete Cache Files",
                    estimatedSavings: cacheBytes,
                    reason: "Caches can be safely cleared and will regenerate as needed."
                )
            )
        }

        if dmgBytes > 0 {
            insights.append(
                StorageInsight(
                    title: "Old DMGs",
                    detail: "Disk images left over from app installations.",
                    estimatedSavings: dmgBytes
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "delete_dmg",
                    title: "Remove Old DMGs",
                    estimatedSavings: dmgBytes,
                    reason: "Installer images only from Downloads, Desktop, and Documents — never Preboot or system folders. Review large os.dmg files carefully."
                )
            )
        }

        if iosBackupBytes > 0 {
            insights.append(
                StorageInsight(
                    title: "Unused iOS backups",
                    detail: "Local iPhone and iPad backup archives.",
                    estimatedSavings: iosBackupBytes
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "delete_ios_backups",
                    title: "Remove Old iOS Backups",
                    estimatedSavings: iosBackupBytes,
                    reason: "Old device backups can be removed if you use iCloud backup."
                )
            )
        }

        if tempExportBytes > 0 {
            insights.append(
                StorageInsight(
                    title: "Temporary exports",
                    detail: "Preview files, thumbnails, and temp exports.",
                    estimatedSavings: tempExportBytes
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "delete_previews",
                    title: "Clear Temporary Exports",
                    estimatedSavings: tempExportBytes,
                    reason: "Temporary files can usually be regenerated."
                )
            )
        }

        if downloadBytes > 50_000_000 {
            insights.append(
                StorageInsight(
                    title: "Downloads folder",
                    detail: "Files accumulated in Downloads.",
                    estimatedSavings: downloadBytes
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "clean_downloads",
                    title: "Remove Old Downloads",
                    estimatedSavings: downloadBytes,
                    reason: "Review and remove installers and files you no longer need."
                )
            )
        }

        if oldVideoBytes > 0 {
            insights.append(
                StorageInsight(
                    title: "Old videos",
                    detail: "Video files not opened in the last two years.",
                    estimatedSavings: oldVideoBytes
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "archive_old_files",
                    title: "Archive Old Videos",
                    estimatedSavings: oldVideoBytes,
                    reason: "Large video files have not been accessed recently."
                )
            )
        }

        let devBytes = try database.categorySize(forDiskID: diskID, category: .development)
        if devBytes > 100_000_000 {
            insights.append(
                StorageInsight(
                    title: "Developer artifacts",
                    detail: "DerivedData, Docker, node_modules, and build caches.",
                    estimatedSavings: devBytes
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "project_purge",
                    title: "Purge Project Artifacts",
                    estimatedSavings: devBytes,
                    reason: "Build folders and dependencies can be regenerated. Use Maintenance → Project Purge for a targeted scan."
                )
            )
        }

        let logBytes = allFiles
            .filter { file in
                let lower = file.path.lowercased()
                return lower.contains("/library/logs/") && file.category != .application
            }
            .reduce(Int64(0)) { $0 + $1.size }
        if logBytes > 50_000_000 {
            insights.append(
                StorageInsight(
                    title: "Log files",
                    detail: "Diagnostic and application logs.",
                    estimatedSavings: logBytes
                )
            )
            recommendations.append(
                RecommendationRecord(
                    type: "delete_logs",
                    title: "Clear Log Files",
                    estimatedSavings: logBytes,
                    reason: "Logs are safe to remove and will regenerate. Use Maintenance → Deep Clean for a full scan."
                )
            )
        }

        if let topCategory = overview.categorySummaries.first {
            insights.append(
                StorageInsight(
                    title: "Largest category: \(topCategory.category.displayName)",
                    detail: "\(topCategory.fileCount) files in this category.",
                    estimatedSavings: 0
                )
            )
        }

        try database.insertRecommendations(recommendations)

        let potential = recommendations.reduce(0) { $0 + $1.estimatedSavings }
        return AnalysisReport(
            overview: overview,
            insights: insights,
            recommendations: recommendations,
            potentialReclaimableSpace: potential
        )
    }

    public func generateLLMReportPrompt(for diskID: Int64) throws -> String {
        let report = try analyze(diskID: diskID)
        let categories = report.overview.categorySummaries
            .map { "\($0.category.rawValue): \(ByteCountFormatter.string(fromByteCount: $0.totalSize, countStyle: .file))" }
            .joined(separator: "\n")

        return """
        Analyze this macOS storage scan and produce a human-readable optimization plan.

        Total indexed: \(ByteCountFormatter.string(fromByteCount: report.overview.totalSize, countStyle: .file))
        Potential reclaimable: \(ByteCountFormatter.string(fromByteCount: report.potentialReclaimableSpace, countStyle: .file))

        Categories:
        \(categories)

        Recommendations:
        \(report.recommendations.map { "- \($0.title): \($0.reason)" }.joined(separator: "\n"))
        """
    }

    public func requestLLMReport(for diskID: Int64) async throws -> String {
        guard let configuration = ollamaConfiguration else {
            let report = try analyze(diskID: diskID)
            return report.insights
                .map { "- \($0.title): \(ByteCountFormatter.string(fromByteCount: $0.estimatedSavings, countStyle: .file)) — \($0.detail)" }
                .joined(separator: "\n")
        }

        let prompt = try generateLLMReportPrompt(for: diskID)
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "prompt": prompt,
            "stream": false,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["response"] as? String ?? "No response from Ollama."
    }
}
