import Foundation
import SwiftUI
import DatabaseKit
import DiskScannerKit
import DuplicateKit
import CleanupKit
import AIKit

enum DiskWiseFormatters {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func formatDuration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "—" }
        let total = Int(interval.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

enum ScanPhase: String, Sendable {
    case idle
    case scanning
    case findingDuplicates
    case analyzing

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .scanning: return "Scanning files"
        case .findingDuplicates: return "Finding duplicates"
        case .analyzing: return "Analyzing storage"
        }
    }
}

enum DetailPane: String, CaseIterable, Identifiable {
    case overview
    case duplicates
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .duplicates: return "Duplicates"
        case .ai: return "Ask DiskWise"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.pie"
        case .duplicates: return "doc.on.doc"
        case .ai: return "sparkles"
        }
    }
}

enum AppStatusKind {
    case ready
    case working
    case success
    case error

    var tint: Color {
        switch self {
        case .ready: return .secondary
        case .working: return .blue
        case .success: return .green
        case .error: return .red
        }
    }

    var icon: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .working: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var disks: [DiskRecord] = []
    @Published var mountedVolumes: [MountedVolume] = []
    @Published var selectedVolumePath: String?
    @Published var selectedDiskID: Int64?
    @Published var overview: StorageOverview?
    @Published var topConsumers: [SpaceConsumer] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var analysisReport: AnalysisReport?
    @Published var scanProgress: ScanProgress?
    @Published var scanPhase: ScanPhase = .idle
    @Published var isScanning = false
    @Published var isAnalyzing = false
    @Published var statusMessage = "Ready to scan"
    @Published var statusKind: AppStatusKind = .ready
    @Published var llmReport = ""
    @Published var showFullDiskAccessPrompt = false
    @Published var fullDiskAccessWizardStep: FullDiskAccessWizardStep = .needsPermission
    @Published var hasFullDiskAccess = false
    @Published var missingExternalVolumePaths: [String] = []
    @Published var selectedPane: DetailPane = .overview
    @Published var aiQuestion = ""
    @Published var aiResponses: [AIChatMessage] = []
    @Published var selectedStorageCategory: String?
    @Published var categoryDetailFiles: [FileRecord] = []
    @Published var hoveredStorageCategory: String?
    @Published var recommendationReview: RecommendationReviewState?

    private let database: DiskWiseDatabase
    private var permissionPollTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var scanStartTime: Date?
    private var lastInsightsRefreshCount = 0
    private let scanEngine: ScanEngine
    private let duplicateEngine: DuplicateEngine
    private let cleanupEngine: CleanupEngine
    private let aiEngine: AIAnalysisEngine
    private let fullDiskAccessPromptKey = "diskwise.hasSeenFullDiskAccessPrompt"

    init() {
        let databaseURL = (try? DiskWiseDatabase.defaultURL()) ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("diskwise.sqlite")
        let database = try! DiskWiseDatabase(path: databaseURL)
        self.database = database
        self.scanEngine = ScanEngine(database: database)
        self.duplicateEngine = DuplicateEngine(database: database)
        self.cleanupEngine = CleanupEngine()
        self.aiEngine = AIAnalysisEngine(database: database)
        reload()
    }

    var isFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: fullDiskAccessPromptKey)
    }

    var shouldShowFullDiskAccessBanner: Bool {
        !showFullDiskAccessPrompt
            && !hasFullDiskAccess
            && (mountedVolumes.isEmpty || !missingExternalVolumePaths.isEmpty)
    }

    var selectedVolume: MountedVolume? {
        guard let selectedVolumePath else { return nil }
        return mountedVolumes.first { $0.mountPath == selectedVolumePath }
    }

    var internalVolumes: [MountedVolume] {
        mountedVolumes.filter(\.isInternal)
    }

    var externalVolumes: [MountedVolume] {
        mountedVolumes.filter { !$0.isInternal }
    }

    var canEjectSelectedVolume: Bool {
        selectedVolume?.isEjectable ?? false
    }

    var hasScanData: Bool {
        overview != nil
    }

    var totalDuplicateSavings: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.reclaimableSize }
    }

    var scanEstimatedRemaining: TimeInterval? {
        guard let progress = scanProgress,
              let start = scanStartTime,
              progress.scannedCount > 100,
              let volume = selectedVolume,
              volume.usedSize > 0 else {
            return nil
        }

        let elapsed = Date().timeIntervalSince(start)
        let rate = Double(progress.bytesIndexed) / elapsed
        guard rate > 0 else { return nil }

        let remainingBytes = Double(max(0, volume.usedSize - progress.bytesIndexed))
        return remainingBytes / rate
    }

    var scanProgressFraction: Double {
        switch scanPhase {
        case .findingDuplicates:
            return max(scanProgressFractionFromBytes, 0.88)
        case .analyzing:
            return max(scanProgressFractionFromBytes, 0.94)
        case .scanning:
            return scanProgressFractionFromBytes
        case .idle:
            return 0
        }
    }

    var scanProgressFractionFromBytes: Double {
        guard let progress = scanProgress,
              let volume = selectedVolume,
              volume.usedSize > 0 else {
            return isScanning ? 0.08 : 0
        }
        return min(1.0, Double(progress.bytesIndexed) / Double(volume.usedSize))
    }

    var scanProgressPercent: Int {
        Int((scanProgressFraction * 100).rounded())
    }

    var scanProgressPercentLabel: String {
        "\(scanProgressPercent)%"
    }

    /// Compact label for the toolbar badge while scanning.
    var toolbarStatusMessage: String {
        if isScanning, let volume = selectedVolume {
            return "Scanning \(volume.name) · \(scanProgressPercentLabel)"
        }
        if isAnalyzing {
            return "Analyzing storage…"
        }
        return statusMessage
    }

    func diskRecord(for volume: MountedVolume) -> DiskRecord? {
        disks.first { $0.mountPath == volume.mountPath }
    }

    func isIndexed(_ volume: MountedVolume) -> Bool {
        diskRecord(for: volume) != nil
    }

    func groupedCategorySummaries(from summaries: [CategorySummary]) -> [(name: String, totalSize: Int64, fileCount: Int)] {
        var grouped: [String: (size: Int64, count: Int)] = [:]
        for summary in summaries {
            let key = summary.category.chartGroup
            var bucket = grouped[key, default: (0, 0)]
            bucket.size += summary.totalSize
            bucket.count += summary.fileCount
            grouped[key] = bucket
        }
        return grouped
            .map { (name: $0.key, totalSize: $0.value.size, fileCount: $0.value.count) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    func subSummaries(forChartGroup name: String) -> [CategorySummary] {
        guard let overview else { return [] }
        return overview.categorySummaries
            .filter { $0.category.chartGroup == name }
            .sorted { $0.totalSize > $1.totalSize }
    }

    func selectStorageCategory(_ name: String?) {
        if selectedStorageCategory == name {
            clearStorageCategorySelection()
            return
        }

        selectedStorageCategory = name
        guard let name, let diskID = selectedDiskID else {
            categoryDetailFiles = []
            return
        }
        categoryDetailFiles = (try? database.topFiles(inChartGroup: name, diskID: diskID, limit: 25)) ?? []
    }

    func clearStorageCategorySelection() {
        selectedStorageCategory = nil
        categoryDetailFiles = []
    }

    private func maybeRefreshInsightsDuringScan(_ progress: ScanProgress) {
        guard isScanning, scanPhase == .scanning else { return }
        guard progress.scannedCount - lastInsightsRefreshCount >= 5_000 else { return }

        lastInsightsRefreshCount = progress.scannedCount

        if selectedDiskID == nil {
            disks = (try? database.allDisks()) ?? []
            selectedDiskID = disks.first(where: { $0.mountPath == selectedVolumePath })?.id
        }
        guard let diskID = selectedDiskID else { return }

        let threshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        overview = try? database.storageOverview(forDiskID: diskID, oldFileThreshold: threshold)
    }

    func reload() {
        disks = (try? database.allDisks()) ?? []
        refreshMountedVolumes()

        if selectedVolumePath == nil {
            selectedVolumePath = mountedVolumes.first?.mountPath
        }

        if let selectedVolumePath,
           let disk = disks.first(where: { $0.mountPath == selectedVolumePath }) {
            selectedDiskID = disk.id
        } else if selectedDiskID == nil {
            selectedDiskID = disks.first?.id
            if let disk = disks.first {
                selectedVolumePath = disk.mountPath
            }
        } else {
            selectedDiskID = nil
        }

        refreshInsights()
    }

    func refreshFromError() {
        reload()
        refreshMountedVolumes()

        guard let volume = selectedVolume ?? mountedVolumes.first else {
            setStatus("Ready to scan", kind: .ready)
            return
        }

        selectedVolumePath = volume.mountPath
        scanVolume(at: URL(fileURLWithPath: volume.mountPath), name: volume.name)
    }

    func refreshMountedVolumes() {
        mountedVolumes = VolumeDiscovery.mountedVolumes()
        missingExternalVolumePaths = VolumeDiscovery.unlistedExternalVolumePaths()

        if let selectedVolumePath,
           !mountedVolumes.contains(where: { $0.mountPath == selectedVolumePath }) {
            self.selectedVolumePath = mountedVolumes.first?.mountPath
        }
    }

    func presentFullDiskAccessOverlay() {
        fullDiskAccessWizardStep = .needsPermission
        showFullDiskAccessPrompt = true
    }

    func presentFullDiskAccessPromptIfNeeded() {
        FullDiskAccess.registerForFullDiskAccess()
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        refreshMountedVolumes()

        if hasFullDiskAccess {
            if isFirstLaunch {
                UserDefaults.standard.set(true, forKey: fullDiskAccessPromptKey)
            }
            return
        }

        guard FullDiskAccess.shouldPromptForAccess(hasSeenPrompt: !isFirstLaunch) else {
            return
        }

        fullDiskAccessWizardStep = .needsPermission
        showFullDiskAccessPrompt = true

        if mountedVolumes.isEmpty {
            setStatus("No drives detected — Full Disk Access required", kind: .error)
        } else if !missingExternalVolumePaths.isEmpty {
            setStatus("Some external drives are hidden — grant Full Disk Access", kind: .error)
        } else {
            setStatus("Grant Full Disk Access to scan all drives", kind: .ready)
        }
    }

    func grantFullDiskAccess() {
        fullDiskAccessWizardStep = .waiting
        showFullDiskAccessPrompt = true
        FullDiskAccess.registerForFullDiskAccess()
        FullDiskAccessSettings.open()
        setStatus("Waiting for Full Disk Access…", kind: .working)
        startPermissionPolling()
    }

    func cancelFullDiskAccessWaiting() {
        stopPermissionPolling()
        fullDiskAccessWizardStep = .needsPermission
        showFullDiskAccessPrompt = false
        UserDefaults.standard.set(true, forKey: fullDiskAccessPromptKey)

        if !hasFullDiskAccess {
            if !missingExternalVolumePaths.isEmpty || mountedVolumes.isEmpty {
                setStatus("External drives may still be hidden without Full Disk Access", kind: .error)
            } else {
                setStatus("Ready to scan", kind: .ready)
            }
        }
    }

    func dismissFullDiskAccessPrompt() {
        stopPermissionPolling()
        UserDefaults.standard.set(true, forKey: fullDiskAccessPromptKey)
        showFullDiskAccessPrompt = false
        fullDiskAccessWizardStep = .needsPermission

        if !hasFullDiskAccess {
            if !missingExternalVolumePaths.isEmpty || mountedVolumes.isEmpty {
                setStatus("External drives may still be hidden without Full Disk Access", kind: .error)
            } else {
                setStatus("Ready to scan", kind: .ready)
            }
        }
    }

    func stopPermissionPollingIfNeeded() {
        stopPermissionPolling()
    }

    func checkPermissionOnAppActivation() {
        guard !hasFullDiskAccess else { return }

        let previouslyMissingDrives = mountedVolumes.isEmpty || !missingExternalVolumePaths.isEmpty
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        refreshMountedVolumes()

        let drivesFullyVisible = !mountedVolumes.isEmpty && missingExternalVolumePaths.isEmpty
        guard hasFullDiskAccess || drivesFullyVisible else { return }

        if showFullDiskAccessPrompt || previouslyMissingDrives {
            handleFullDiskAccessGranted(startScan: true)
        }
    }

    func refreshDrivesAfterPermissionChange() {
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        refreshMountedVolumes()

        if hasFullDiskAccess || (missingExternalVolumePaths.isEmpty && !mountedVolumes.isEmpty) {
            showFullDiskAccessPrompt = false
            fullDiskAccessWizardStep = .needsPermission
            setStatus("Drives refreshed — \(mountedVolumes.count) available", kind: .success)
        } else if mountedVolumes.isEmpty {
            setStatus("Still no drives detected — check Full Disk Access", kind: .error)
        } else {
            setStatus("Some external drives are still hidden", kind: .error)
        }
    }

    private func startPermissionPolling() {
        stopPermissionPolling()
        permissionPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                checkPermissionStatus()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = nil
    }

    private func checkPermissionStatus() {
        hasFullDiskAccess = FullDiskAccess.hasFullDiskAccess()
        refreshMountedVolumes()

        let drivesFullyVisible = !mountedVolumes.isEmpty && missingExternalVolumePaths.isEmpty
        if hasFullDiskAccess || drivesFullyVisible {
            handleFullDiskAccessGranted(startScan: true)
        }
    }

    private func handleFullDiskAccessGranted(startScan: Bool) {
        guard fullDiskAccessWizardStep != .granted else { return }

        stopPermissionPolling()
        hasFullDiskAccess = true
        UserDefaults.standard.set(true, forKey: fullDiskAccessPromptKey)
        fullDiskAccessWizardStep = .granted
        setStatus("Full Disk Access granted", kind: .success)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            showFullDiskAccessPrompt = false
            fullDiskAccessWizardStep = .needsPermission

            guard startScan else {
                setStatus("Drives refreshed — \(mountedVolumes.count) available", kind: .success)
                return
            }

            guard let volume = selectedVolume ?? mountedVolumes.first else {
                setStatus("Permission granted — select a drive to scan", kind: .success)
                return
            }

            selectVolume(volume, autoScan: true)
        }
    }

    func selectVolume(_ volume: MountedVolume, autoScan: Bool = false) {
        selectedVolumePath = volume.mountPath
        if let disk = diskRecord(for: volume) {
            selectedDiskID = disk.id
        } else {
            selectedDiskID = nil
        }
        refreshInsights()
        setStatus("Selected \(volume.name)", kind: .ready)

        if autoScan && !isIndexed(volume) && !isScanning {
            scanVolume(at: URL(fileURLWithPath: volume.mountPath), name: volume.name)
        }
    }

    func scanSelectedVolume() {
        guard let volume = selectedVolume else {
            setStatus("Select a drive from the sidebar first", kind: .error)
            return
        }
        scanVolume(at: URL(fileURLWithPath: volume.mountPath), name: volume.name)
    }

    func scanInternalDrive() {
        if let internalVolume = internalVolumes.first {
            selectedVolumePath = internalVolume.mountPath
            scanVolume(at: URL(fileURLWithPath: internalVolume.mountPath), name: internalVolume.name)
        } else if let first = mountedVolumes.first {
            selectedVolumePath = first.mountPath
            scanVolume(at: URL(fileURLWithPath: first.mountPath), name: first.name)
        }
    }

    func ejectSelectedVolume() {
        guard let volume = selectedVolume else {
            setStatus("Select a drive to eject", kind: .error)
            return
        }
        ejectVolume(volume)
    }

    func ejectVolume(_ volume: MountedVolume) {
        guard volume.isEjectable else {
            setStatus("\(volume.name) cannot be ejected", kind: .error)
            return
        }

        if isScanning, selectedVolumePath == volume.mountPath {
            cancelScan()
        }

        setStatus("Ejecting \(volume.name)…", kind: .working)

        Task { @MainActor in
            do {
                try VolumeEject.eject(volume)
                refreshMountedVolumes()
                if selectedVolumePath == volume.mountPath {
                    selectedVolumePath = mountedVolumes.first?.mountPath
                    selectedDiskID = nil
                    overview = nil
                    topConsumers = []
                    duplicateGroups = []
                    analysisReport = nil
                }
                reload()
                setStatus("Ejected \(volume.name)", kind: .success)
            } catch {
                refreshMountedVolumes()
                setStatus("Could not eject \(volume.name): \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        scanPhase = .idle
        scanProgress = nil
        scanStartTime = nil
        setStatus("Scan cancelled", kind: .ready)
    }

    func refreshInsights() {
        guard let diskID = selectedDiskID else {
            overview = nil
            topConsumers = []
            duplicateGroups = []
            analysisReport = nil
            return
        }

        let threshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        overview = try? database.storageOverview(forDiskID: diskID, oldFileThreshold: threshold)
        topConsumers = (try? database.topConsumers(forDiskID: diskID, limit: 8)) ?? []
        duplicateGroups = (try? duplicateEngine.loadGroups(forDiskID: diskID)) ?? []
        analysisReport = try? aiEngine.analyze(diskID: diskID)
    }

    func scanVolume(at url: URL, name: String? = nil) {
        scanTask?.cancel()
        isScanning = true
        scanPhase = .scanning
        scanStartTime = Date()
        lastInsightsRefreshCount = 0
        clearStorageCategorySelection()
        let volumeName = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        selectedVolumePath = url.path
        setStatus("Scanning \(volumeName)…", kind: .working)

        scanTask = Task.detached { [weak self] in
            guard let self else { return }
            do {
                let summary = try self.scanEngine.scanVolume(
                    name: volumeName,
                    mountPath: url,
                    onProgress: { progress in
                        Task { @MainActor in
                            self.scanProgress = progress
                            self.maybeRefreshInsightsDuringScan(progress)
                            self.setStatus(
                                "Scanning \(volumeName) · \(progress.scannedCount.formatted()) files · \(self.scanProgressPercentLabel)",
                                kind: .working
                            )
                        }
                    },
                    isCancelled: {
                        Task.isCancelled
                    }
                )

                await MainActor.run {
                    self.scanPhase = .findingDuplicates
                    self.setStatus("Finding duplicates on \(volumeName)…", kind: .working)
                }

                let duplicateSummary = try self.duplicateEngine.detectAll(forDiskID: summary.diskID)

                await MainActor.run {
                    self.scanPhase = .analyzing
                    self.setStatus("Analyzing storage on \(volumeName)…", kind: .working)
                }

                _ = try self.aiEngine.analyze(diskID: summary.diskID)

                await MainActor.run {
                    self.isScanning = false
                    self.scanPhase = .idle
                    self.scanProgress = nil
                    self.scanStartTime = nil
                    self.selectedDiskID = summary.diskID
                    self.selectedVolumePath = url.path
                    self.reload()
                    self.setStatus(
                        "Scan complete · \(duplicateSummary.groupsFound) duplicate groups · \(DiskWiseFormatters.bytes.string(fromByteCount: duplicateSummary.reclaimableBytes)) reclaimable",
                        kind: .success
                    )
                }
            } catch {
                await MainActor.run {
                    self.isScanning = false
                    self.scanPhase = .idle
                    self.scanProgress = nil
                    self.scanStartTime = nil
                    if error.localizedDescription.contains("cancelled") {
                        self.setStatus("Scan cancelled", kind: .ready)
                    } else {
                        self.setStatus("Scan failed: \(error.localizedDescription)", kind: .error)
                    }
                }
            }
        }
    }

    func generateLLMReport() {
        guard let diskID = selectedDiskID else {
            setStatus("Scan a drive first to generate AI recommendations", kind: .error)
            return
        }
        isAnalyzing = true
        setStatus("Generating AI report...", kind: .working)

        Task {
            do {
                let report = try await aiEngine.requestLLMReport(for: diskID)
                await MainActor.run {
                    self.llmReport = report
                    self.isAnalyzing = false
                    self.setStatus("AI report ready", kind: .success)
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.setStatus("AI report unavailable: \(error.localizedDescription)", kind: .error)
                }
            }
        }
    }

    func askAI(question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        aiQuestion = ""
        aiResponses.append(AIChatMessage(role: .user, text: trimmed))

        guard let report = analysisReport else {
            aiResponses.append(AIChatMessage(
                role: .assistant,
                text: "Scan a drive first so I can analyze your storage and answer questions."
            ))
            return
        }

        let answer = Self.answerQuestion(trimmed, report: report, consumers: topConsumers)
        aiResponses.append(AIChatMessage(role: .assistant, text: answer))
    }

    private static func answerQuestion(_ question: String, report: AnalysisReport, consumers: [SpaceConsumer]) -> String {
        let lower = question.lowercased()

        if lower.contains("most") || lower.contains("consuming") || lower.contains("full") {
            if let top = consumers.first {
                let categories = report.overview.categorySummaries.prefix(3)
                    .map { "\($0.category.displayName): \(DiskWiseFormatters.bytes.string(fromByteCount: $0.totalSize))" }
                    .joined(separator: ", ")
                return "Your biggest space consumer is **\(top.name)** at \(DiskWiseFormatters.bytes.string(fromByteCount: top.totalSize)). Top categories: \(categories)."
            }
        }

        if lower.contains("safely") || lower.contains("remove") || lower.contains("delete") {
            let recs = report.recommendations.prefix(4)
                .map { "• \($0.title) — save \(DiskWiseFormatters.bytes.string(fromByteCount: $0.estimatedSavings))" }
                .joined(separator: "\n")
            return "Based on your scan, these are safe starting points:\n\(recs)\n\nAlways preview before moving files to Trash."
        }

        if lower.contains("duplicate") {
            let savings = report.overview.duplicateSavings
            return savings > 0
                ? "I found \(DiskWiseFormatters.bytes.string(fromByteCount: savings)) in duplicate files. Open the Duplicates tab to review groups and clean up safely."
                : "No significant duplicate files were detected in the latest scan."
        }

        if lower.contains("video") || lower.contains("watch") {
            let mediaSize = report.overview.categorySummaries
                .filter { $0.category == .video || $0.category == .photo }
                .reduce(Int64(0)) { $0 + $1.totalSize }
            return "Media files use \(DiskWiseFormatters.bytes.string(fromByteCount: mediaSize)). Check the Overview for your largest folders and consider archiving old exports."
        }

        let reclaimable = DiskWiseFormatters.bytes.string(fromByteCount: report.potentialReclaimableSpace)
        return "You could potentially reclaim **\(reclaimable)**. Top insight: \(report.insights.first?.title ?? "Run a scan for detailed analysis."). Try asking about duplicates, caches, or what's using the most space."
    }

    func handleRecommendation(_ recommendation: RecommendationRecord) {
        reviewRecommendation(recommendation)
    }

    func reviewRecommendation(_ recommendation: RecommendationRecord) {
        guard let diskID = selectedDiskID else {
            setStatus("Scan a drive first", kind: .error)
            return
        }

        let threshold = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
        let files = (try? database.files(
            forRecommendationType: recommendation.type,
            diskID: diskID,
            oldFileThreshold: threshold,
            limit: 500
        )) ?? []

        if recommendation.type == "duplicate_cleanup" && files.isEmpty {
            selectedPane = .duplicates
            setStatus("Review duplicate groups in the Duplicates tab", kind: .ready)
            return
        }

        recommendationReview = RecommendationReviewState(
            recommendation: recommendation,
            files: files,
            selectedFileIDs: Set(files.compactMap(\.id))
        )
    }

    func dismissRecommendationReview() {
        recommendationReview = nil
    }

    func executeRecommendationCleanup(files: [FileRecord], recommendation: RecommendationRecord) {
        let preview = cleanupEngine.preview(files: files, keepFirstInEachGroup: false)
        executeCleanup(preview: preview)
        recommendationReview = nil
        setStatus("Completed \(recommendation.title)", kind: .success)
    }

    func previewCleanup(for group: DuplicateGroup) -> CleanupPreview {
        cleanupEngine.preview(files: group.files, keepFirstInEachGroup: true)
    }

    func executeCleanup(preview: CleanupPreview) {
        do {
            let result = try cleanupEngine.execute(preview: preview)
            setStatus(
                "Moved \(result.movedCount) files to Trash (\(DiskWiseFormatters.bytes.string(fromByteCount: result.movedBytes)))",
                kind: .success
            )
            refreshInsights()
        } catch {
            setStatus("Cleanup failed: \(error.localizedDescription)", kind: .error)
        }
    }

    private func setStatus(_ message: String, kind: AppStatusKind) {
        statusMessage = message
        statusKind = kind
    }
}

struct AIChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}
