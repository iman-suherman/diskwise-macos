import AIKit
import AppKit
import Foundation
import MaintenanceKit

@MainActor
final class StartupAppsMonitor: ObservableObject {
    static let shared = StartupAppsMonitor()

    @Published private(set) var scanResult: StartupAppsScanResult?
    @Published private(set) var report: StartupAppsAnalysisReport?
    @Published private(set) var isScanning = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var streamingAnalysis = ""
    @Published private(set) var isStreamingAnalysis = false
    @Published private(set) var lastScannedAt: Date?
    @Published private(set) var aiProviderLabel = "Rule-based"
    @Published private(set) var scanDiagnostics: StartupAppsScanDiagnostics?
    @Published var errorMessage: String?

    private let scanner = StartupAppsScanner()
    private var analysisEngine = StartupAppsAnalysisEngine()
    private var scanTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?

    private init() {}

    deinit {
        scanTask?.cancel()
        analysisTask?.cancel()
    }

    func refreshConfiguration(from settings: AppSettings) {
        analysisEngine.updateConsultantConfiguration(settings.aiProviderConfiguration)
    }

    func scanAndAnalyze(force: Bool = false) {
        guard !isScanning else { return }
        if !force, scanResult != nil, report != nil { return }

        scanTask?.cancel()
        analysisTask?.cancel()
        errorMessage = nil

        scanTask = Task {
            isScanning = true
            defer { isScanning = false }

            let result = await Task.detached(priority: .userInitiated) {
                StartupAppsScanner().scan()
            }.value

            guard !Task.isCancelled else { return }
            scanResult = result
            scanDiagnostics = result.diagnostics
            lastScannedAt = result.scannedAt

            if result.items.isEmpty {
                report = StartupAppsAnalysisReport(
                    scannedAt: result.scannedAt,
                    items: [],
                    analyses: [],
                    summary: emptyScanSummary(diagnostics: result.diagnostics)
                )
                return
            }

            await runAnalysis(for: result)
        }
    }

    func reanalyze() {
        guard let scanResult else {
            scanAndAnalyze(force: true)
            return
        }
        analysisTask?.cancel()
        analysisTask = Task {
            await runAnalysis(for: scanResult)
        }
    }

    private func runAnalysis(for result: StartupAppsScanResult) async {
        isAnalyzing = true
        isStreamingAnalysis = true
        streamingAnalysis = ""
        defer {
            isAnalyzing = false
            isStreamingAnalysis = false
        }

        let status = await analysisEngine.providerStatus()
        aiProviderLabel = status.displayName

        if status.isGenerativeAvailable {
            let stream = analysisEngine.streamAnalyze(scanResult: result)
            var lastPartial = ""

            do {
                for try await partial in stream {
                    guard !Task.isCancelled else { return }
                    lastPartial = partial
                    streamingAnalysis = partial
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            if !lastPartial.isEmpty {
                report = analysisEngine.report(from: result, aiText: lastPartial)
                return
            }
        }

        report = await analysisEngine.analyze(scanResult: result)
    }

    func openLoginItemsSettings() {
        MenuBarMonitorController.openLoginItemsSettingsForApproval()
    }

    func openAutomationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        ]
        for link in urls {
            if let url = URL(string: link), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func emptyScanSummary(diagnostics: StartupAppsScanDiagnostics) -> String {
        if diagnostics.needsPermissionSetup {
            return "Grant the permissions described on the right, then refresh to list Open at Login and App Background Activity items."
        }
        return "No startup apps were found on this Mac."
    }
}
