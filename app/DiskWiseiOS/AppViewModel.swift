import Foundation
import PhotosKit
import SwiftUI

enum DemoScreenshotRoute: String {
    case dashboard
    case recommendations
    case bucket
    case confirm

    static var fromEnvironment: DemoScreenshotRoute? {
        guard ProcessInfo.processInfo.environment["DISKWISE_DEMO"] == "1" else { return nil }
        let raw = ProcessInfo.processInfo.environment["DISKWISE_DEMO_ROUTE"] ?? "dashboard"
        return DemoScreenshotRoute(rawValue: raw) ?? .dashboard
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var authorization: PhotosAuthorizationStatus = .notDetermined
    @Published var isScanning = false
    @Published var scanProgress: PhotosScanProgress?
    @Published var report: PhotosLibraryReport = .empty
    @Published var assetsByID: [String: PhotoAssetRecord] = [:]
    @Published var selectedIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var lastCleanupCount: Int?
    @Published var isCleaning = false
    @Published var screenshotInsights: [String: PhotosScreenshotInsight] = [:]
    /// Last bucket that applied a default selection — avoids leftover IDs from another screen.
    private var selectionContext: String?
    /// App Store screenshot deep-link (set only when DISKWISE_DEMO=1).
    let demoRoute: DemoScreenshotRoute?

    private let consultant = PhotosConsultantService()
    private let cleanup = PhotosCleanupEngine()
    private var screenshotOCRCompleted: Set<String> = []

    init() {
        demoRoute = DemoScreenshotRoute.fromEnvironment
        authorization = consultant.authorizationStatus()
        if demoRoute != nil {
            loadDemoReport()
        }
    }

    /// Screenshots bucket — used by `bucket` / `confirm` App Store routes.
    var demoBucketSummary: PhotosBucketSummary? {
        report.buckets.first { $0.bucket == .screenshots } ?? report.buckets.first
    }

    /// Highest-savings recommendation bucket — used by `recommendations` route (must differ from dashboard).
    var demoRecommendationSummary: PhotosBucketSummary? {
        guard let rec = report.recommendations.first else { return nil }
        return PhotosBucketSummary(
            bucket: rec.bucket,
            assetIDs: rec.assetIDs,
            reclaimableBytes: rec.estimatedSavings
        )
    }

    private func loadDemoReport() {
        authorization = .authorized
        let day = Date()
        // Rich enough for 13" iPad screenshots — sparse lists look like placeholders to App Review.
        var assets: [PhotoAssetRecord] = [
            PhotoAssetRecord(id: "d1", mediaType: .image, byteSize: 4_200_000, pixelWidth: 4032, pixelHeight: 3024, creationDate: day),
            PhotoAssetRecord(id: "d2", mediaType: .image, byteSize: 4_200_000, pixelWidth: 4032, pixelHeight: 3024, creationDate: day),
            PhotoAssetRecord(id: "d3", mediaType: .image, byteSize: 3_800_000, pixelWidth: 4032, pixelHeight: 3024, creationDate: day.addingTimeInterval(-3_600)),
            PhotoAssetRecord(id: "d4", mediaType: .image, byteSize: 3_800_000, pixelWidth: 4032, pixelHeight: 3024, creationDate: day.addingTimeInterval(-3_600)),
            PhotoAssetRecord(id: "v1", mediaType: .video, byteSize: 420_000_000, pixelWidth: 1920, pixelHeight: 1080, durationSeconds: 184, creationDate: day.addingTimeInterval(-86400 * 40)),
            PhotoAssetRecord(id: "v2", mediaType: .video, byteSize: 186_000_000, pixelWidth: 1920, pixelHeight: 1080, durationSeconds: 96, creationDate: day.addingTimeInterval(-86400 * 12)),
            PhotoAssetRecord(id: "v3", mediaType: .video, byteSize: 112_000_000, pixelWidth: 1280, pixelHeight: 720, durationSeconds: 64, creationDate: day.addingTimeInterval(-86400 * 90)),
            PhotoAssetRecord(id: "o1", mediaType: .image, byteSize: 3_100_000, pixelWidth: 3000, pixelHeight: 2000, creationDate: day.addingTimeInterval(-86400 * 800)),
            PhotoAssetRecord(id: "o2", mediaType: .image, byteSize: 2_400_000, pixelWidth: 3000, pixelHeight: 2000, creationDate: day.addingTimeInterval(-86400 * 900)),
            PhotoAssetRecord(id: "o3", mediaType: .image, byteSize: 2_100_000, pixelWidth: 2400, pixelHeight: 1600, creationDate: day.addingTimeInterval(-86400 * 1100)),
        ]
        let shotSizes: [Int64] = [890_000, 720_000, 640_000, 580_000, 510_000, 470_000, 430_000, 390_000]
        for (index, size) in shotSizes.enumerated() {
            assets.append(
                PhotoAssetRecord(
                    id: "s\(index + 1)",
                    mediaType: .image,
                    byteSize: size,
                    pixelWidth: 1170,
                    pixelHeight: 2532,
                    creationDate: day.addingTimeInterval(TimeInterval(-86_400 * (index + 3))),
                    isScreenshot: true,
                    originalFilename: index == 0
                        ? "WhatsApp Image.png"
                        : "Screenshot 2026-09-\(String(format: "%02d", 12 - index)).png"
                )
            )
        }
        assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        report = PhotosInsightEngine().analyze(assets)
        seedScreenshotInsights(ocrByID: [
            "s1": "WhatsApp\nYesterday",
            "s2": "Settings\nWi-Fi",
        ])
        switch demoRoute {
        case .recommendations:
            if let summary = demoRecommendationSummary {
                selectedIDs = Set(summary.assetIDs)
            }
        case .bucket, .confirm:
            if let summary = demoBucketSummary {
                selectedIDs = Set(summary.assetIDs)
            }
        case .dashboard, .none:
            break
        }
    }

    var canScan: Bool { authorization.canReadLibrary }

    func refreshAuthorization() {
        authorization = consultant.authorizationStatus()
    }

    func requestAccess() async {
        authorization = await consultant.requestAuthorization()
        if authorization.canReadLibrary {
            await scan()
        }
    }

    func scan() async {
        if demoRoute != nil {
            loadDemoReport()
            return
        }
        guard canScan else {
            errorMessage = PhotosKitError.notAuthorized.localizedDescription
            return
        }
        isScanning = true
        scanProgress = PhotosScanProgress(phase: "Starting", processedCount: 0, totalCount: 1)
        errorMessage = nil
        lastCleanupCount = nil
        defer {
            isScanning = false
            scanProgress = nil
        }
        do {
            let result = try await consultant.scan { [weak self] progress in
                Task { @MainActor in
                    self?.scanProgress = progress
                }
            }
            assetsByID = Dictionary(uniqueKeysWithValues: result.assets.map { ($0.id, $0) })
            report = result.report
            selectedIDs = []
            selectionContext = nil
            screenshotOCRCompleted = []
            seedScreenshotInsights()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectAll(for summary: PhotosBucketSummary) {
        selectedIDs = Set(summary.assetIDs)
    }

    func selectDefault(for summary: PhotosBucketSummary) {
        selectionContext = summary.id
        if summary.bucket == .screenshots {
            selectedIDs = []
            return
        }
        if summary.bucket == .exactDuplicates || summary.bucket == .similar {
            selectedIDs = Set(duplicateGroups(for: summary).flatMap(\.suggestedCleanupIDs))
            return
        }
        selectedIDs = Set(summary.assetIDs)
    }

    /// Replace stale selection when opening a different bucket (e.g. 102 leftover IDs).
    func ensureSelection(for summary: PhotosBucketSummary) {
        if selectionContext != summary.id {
            selectDefault(for: summary)
        }
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    /// Duplicate / similar groups that feed this bucket (includes the suggested keep copy).
    func duplicateGroups(for summary: PhotosBucketSummary) -> [PhotosDuplicateGroup] {
        let source: [PhotosDuplicateGroup]
        switch summary.bucket {
        case .exactDuplicates:
            source = report.exactDuplicateGroups
        case .similar:
            source = report.similarGroups
        default:
            return []
        }
        let cleanupIDs = Set(summary.assetIDs)
        return source.filter { !Set($0.suggestedCleanupIDs).isDisjoint(with: cleanupIDs) }
    }

    /// Keep `id` in the group; mark every other member for cleanup.
    func keepOnly(_ id: String, in group: PhotosDuplicateGroup) {
        let memberIDs = Set(group.assets.map(\.id))
        selectedIDs.subtract(memberIDs)
        selectedIDs.formUnion(memberIDs.filter { $0 != id })
    }

    var selectedReclaimableBytes: Int64 {
        selectedIDs.compactMap { assetsByID[$0]?.byteSize }.reduce(0, +)
    }

    func moveSelectedToRecentlyDeleted() async {
        _ = await moveToRecentlyDeleted(ids: Array(selectedIDs), rescan: true)
    }

    /// Moves items to Recently Deleted. Returns false if nothing was moved.
    func moveToRecentlyDeleted(ids: [String], rescan: Bool) async -> Bool {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return false }
        isCleaning = true
        errorMessage = nil
        defer { isCleaning = false }
        do {
            let count = try await cleanup.moveToRecentlyDeleted(ids: unique)
            lastCleanupCount = count
            selectedIDs.subtract(unique)
            for id in unique {
                assetsByID.removeValue(forKey: id)
                screenshotInsights.removeValue(forKey: id)
            }
            if rescan {
                await scan()
            }
            return count > 0
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func seedScreenshotInsights(ocrByID: [String: String] = [:]) {
        let ids = report.buckets.first { $0.bucket == .screenshots }?.assetIDs ?? []
        var next = screenshotInsights
        for id in ids {
            guard let asset = assetsByID[id] else { continue }
            if next[id] != nil, ocrByID[id] == nil { continue }
            next[id] = PhotosScreenshotInsightEngine.insight(
                for: asset,
                ocrText: ocrByID[id] ?? ""
            )
        }
        screenshotInsights = next
    }

    /// Refine screenshot labels with on-device OCR (no-op in App Store demo mode).
    func refineScreenshotInsights(for ids: [String]) async {
        guard demoRoute == nil else { return }
        let pending = ids.filter { id in
            assetsByID[id] != nil && !screenshotOCRCompleted.contains(id)
        }
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: (String, String).self) { group in
            var queued = 0
            for id in pending {
                if queued >= 4 {
                    if let (assetID, ocr) = await group.next() {
                        applyOCR(assetID: assetID, ocr: ocr)
                    }
                    queued -= 1
                }
                queued += 1
                group.addTask {
                    let ocr = await ScreenshotOCR.recognizedText(assetID: id)
                    return (id, ocr)
                }
            }
            for await (assetID, ocr) in group {
                applyOCR(assetID: assetID, ocr: ocr)
            }
        }
    }

    private func applyOCR(assetID: String, ocr: String) {
        screenshotOCRCompleted.insert(assetID)
        guard !ocr.isEmpty, let asset = assetsByID[assetID] else { return }
        screenshotInsights[assetID] = PhotosScreenshotInsightEngine.insight(for: asset, ocrText: ocr)
    }

    func rankedScreenshotIDs(_ ids: [String]) -> [String] {
        ids.sorted { lhs, rhs in
            let left = screenshotInsights[lhs]
            let right = screenshotInsights[rhs]
            let leftRank = actionRank(left?.action)
            let rightRank = actionRank(right?.action)
            if leftRank != rightRank { return leftRank < rightRank }
            return (left?.keepScore ?? 50) < (right?.keepScore ?? 50)
        }
    }

    private func actionRank(_ action: PhotosScreenshotKeepAction?) -> Int {
        switch action {
        case .trash: return 0
        case .review, .none: return 1
        case .keep: return 2
        }
    }
}
