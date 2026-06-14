import Foundation
import AIKit

@MainActor
final class MemoryAnalyzerMonitor: ObservableObject {
    static let shared = MemoryAnalyzerMonitor()

    @Published private(set) var samples: [MemorySampleRecord] = []
    @Published private(set) var report: MemoryAnalysisReport?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var lastAIAnalysisAt: Date?
    @Published private(set) var aiProviderLabel = "Rule-based"
    @Published private(set) var isRunning = false

    private let maxSamples = 24
    private let notificationCooldown: TimeInterval = 20 * 60
    private let periodicAIInterval: Duration = .seconds(600)
    private let sampleProcessLimit = 5

    private var sampleTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var periodicAITask: Task<Void, Never>?
    private var analysisEngine: MemoryAnalysisEngine
    private var samplesSinceLastAnalysis = 0
    private var settings: AppSettings = .shared
    private var insightFingerprint: String?
    private var lastNotificationAt: Date?

    private init() {
        analysisEngine = MemoryAnalysisEngine()
    }

    deinit {
        sampleTask?.cancel()
        analysisTask?.cancel()
        periodicAITask?.cancel()
    }

    func startIfNeeded(settings: AppSettings = .shared) {
        self.settings = settings
        refreshConfiguration(from: settings)
        guard settings.memoryAnalyzerEnabled else {
            stop()
            return
        }
        guard !isRunning else { return }
        isRunning = true
        MemoryInsightNotificationService.shared.prepare()
        startSampling()
        startPeriodicAI()
        Task {
            await MemoryInsightNotificationService.shared.requestAuthorizationIfNeeded()
        }
    }

    func applySettings(_ settings: AppSettings) {
        self.settings = settings
        refreshConfiguration(from: settings)
        if settings.memoryAnalyzerEnabled {
            startIfNeeded(settings: settings)
        } else {
            stop()
        }
    }

    func stop() {
        sampleTask?.cancel()
        analysisTask?.cancel()
        periodicAITask?.cancel()
        sampleTask = nil
        analysisTask = nil
        periodicAITask = nil
        isRunning = false
    }

    func refreshConfiguration(from settings: AppSettings) {
        self.settings = settings
        analysisEngine.updateConsultantConfiguration(settings.aiProviderConfiguration)
    }

    func captureNow() {
        appendSample()
        scheduleAnalysis(force: true)
    }

    func refreshAIAnalysis() {
        scheduleAnalysis(force: true)
    }

    var primaryActionableRecommendation: MemoryActionRecommendation? {
        report?.recommendations.first { $0.actionKind != .informational && $0.priority >= 65 }
    }

    var actionableRecommendations: [MemoryActionRecommendation] {
        report?.recommendations.filter { $0.actionKind != .informational } ?? []
    }

    private func startSampling() {
        sampleTask?.cancel()
        sampleTask = Task { @MainActor in
            appendSample()
            while !Task.isCancelled {
                let interval = sampleInterval()
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                appendSample()
                samplesSinceLastAnalysis += 1
                if samplesSinceLastAnalysis >= 3 {
                    scheduleAnalysis(force: false)
                }
            }
        }
    }

    private func startPeriodicAI() {
        periodicAITask?.cancel()
        periodicAITask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: periodicAIInterval)
                guard !Task.isCancelled, samples.count >= 2 else { continue }
                scheduleAnalysis(force: true)
            }
        }
    }

    private func sampleInterval() -> Duration {
        guard let latest = samples.last else { return .seconds(30) }
        if latest.usedPercent >= 85 { return .seconds(15) }
        if latest.usedPercent >= 70 { return .seconds(20) }
        return .seconds(30)
    }

    private func appendSample() {
        let snapshot = SystemHealthMonitorCore.capture(volume: nil, processLimit: sampleProcessLimit)
        let record = MemorySampleRecord(
            timestamp: Date(),
            usedPercent: snapshot.memoryUsedPercent,
            usedBytes: snapshot.memoryUsedBytes,
            physicalBytes: snapshot.physicalMemoryBytes,
            topProcesses: snapshot.topMemoryProcesses.map {
                MemoryProcessSample(name: $0.name, memoryBytes: $0.memoryBytes)
            }
        )
        samples.append(record)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        lastSampleAt = record.timestamp
    }

    private func scheduleAnalysis(force: Bool) {
        guard force || samples.count >= 2 else { return }
        analysisTask?.cancel()
        analysisTask = Task { @MainActor in
            isAnalyzing = true
            defer {
                isAnalyzing = false
                samplesSinceLastAnalysis = 0
            }

            let status = await analysisEngine.providerStatus()
            aiProviderLabel = status.isGenerativeAvailable ? status.displayName : "Rule-based"

            let result = await analysisEngine.analyze(samples: samples)
            guard !Task.isCancelled else { return }
            report = result
            lastAIAnalysisAt = Date()
            await deliverInsightNotificationIfNeeded(for: result)
        }
    }

    private func deliverInsightNotificationIfNeeded(for report: MemoryAnalysisReport) async {
        guard settings.memoryAnalyzerNotificationsEnabled else { return }
        if let lastNotificationAt,
           Date().timeIntervalSince(lastNotificationAt) < notificationCooldown {
            return
        }

        let previous = insightFingerprint
        let updated = await MemoryInsightNotificationService.shared.notifyIfNeeded(
            for: report,
            previousFingerprint: previous,
            notificationsEnabled: settings.memoryAnalyzerNotificationsEnabled
        )

        guard updated != previous else { return }
        insightFingerprint = updated
        lastNotificationAt = Date()
    }
}
