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
    /// App Store screenshot deep-link (set only when DISKWISE_DEMO=1).
    let demoRoute: DemoScreenshotRoute?

    private let consultant = PhotosConsultantService()
    private let cleanup = PhotosCleanupEngine()

    init() {
        demoRoute = DemoScreenshotRoute.fromEnvironment
        authorization = consultant.authorizationStatus()
        if demoRoute != nil {
            loadDemoReport()
        }
    }

    var demoBucketSummary: PhotosBucketSummary? {
        report.buckets.first { $0.bucket == .screenshots } ?? report.buckets.first
    }

    private func loadDemoReport() {
        authorization = .authorized
        let day = Date()
        let assets = [
            PhotoAssetRecord(id: "d1", mediaType: .image, byteSize: 4_200_000, pixelWidth: 4032, pixelHeight: 3024, creationDate: day),
            PhotoAssetRecord(id: "d2", mediaType: .image, byteSize: 4_200_000, pixelWidth: 4032, pixelHeight: 3024, creationDate: day),
            PhotoAssetRecord(id: "s1", mediaType: .image, byteSize: 890_000, pixelWidth: 1170, pixelHeight: 2532, creationDate: day, isScreenshot: true),
            PhotoAssetRecord(id: "s2", mediaType: .image, byteSize: 720_000, pixelWidth: 1170, pixelHeight: 2532, creationDate: day.addingTimeInterval(-86_400), isScreenshot: true),
            PhotoAssetRecord(id: "v1", mediaType: .video, byteSize: 420_000_000, pixelWidth: 1920, pixelHeight: 1080, durationSeconds: 184, creationDate: day.addingTimeInterval(-86400 * 40)),
            PhotoAssetRecord(id: "o1", mediaType: .image, byteSize: 3_100_000, pixelWidth: 3000, pixelHeight: 2000, creationDate: day.addingTimeInterval(-86400 * 800)),
        ]
        assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        report = PhotosInsightEngine().analyze(assets)
        if demoRoute == .bucket || demoRoute == .confirm, let summary = demoBucketSummary {
            selectedIDs = Set(summary.assetIDs)
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectDefault(for summary: PhotosBucketSummary) {
        selectedIDs = Set(summary.assetIDs)
    }

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    var selectedReclaimableBytes: Int64 {
        selectedIDs.compactMap { assetsByID[$0]?.byteSize }.reduce(0, +)
    }

    func moveSelectedToRecentlyDeleted() async {
        guard !selectedIDs.isEmpty else { return }
        isCleaning = true
        errorMessage = nil
        defer { isCleaning = false }
        do {
            let count = try await cleanup.moveToRecentlyDeleted(ids: Array(selectedIDs))
            lastCleanupCount = count
            selectedIDs = []
            await scan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
