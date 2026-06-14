import Foundation
import AIKit

@MainActor
final class MemoryAnalyzerMonitor: ObservableObject {
    static let shared = MemoryAnalyzerMonitor()

    @Published private(set) var samples: [MemorySampleRecord] = []
    @Published private(set) var report: MemoryAnalysisReport?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var aiProviderLabel = "Rule-based"

    private let maxSamples = 48
    private var sampleTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var analysisEngine: MemoryAnalysisEngine
    private var samplesSinceLastAnalysis = 0

    private init() {
        analysisEngine = MemoryAnalysisEngine()
        startSampling()
    }

    deinit {
        sampleTask?.cancel()
        analysisTask?.cancel()
    }

    func refreshConfiguration(from settings: AppSettings) {
        analysisEngine.updateConsultantConfiguration(settings.aiProviderConfiguration)
    }

    func captureNow() {
        appendSample()
        scheduleAnalysis(force: true)
    }

    func refreshAIAnalysis() {
        scheduleAnalysis(force: true)
    }

    private func startSampling() {
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

    private func sampleInterval() -> Duration {
        guard let latest = samples.last else { return .seconds(30) }
        if latest.usedPercent >= 85 { return .seconds(15) }
        if latest.usedPercent >= 70 { return .seconds(20) }
        return .seconds(30)
    }

    private func appendSample() {
        let snapshot = SystemHealthMonitorCore.capture(volume: nil, processLimit: 12)
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
        }
    }
}
