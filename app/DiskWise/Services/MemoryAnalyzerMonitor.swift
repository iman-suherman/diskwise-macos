import Foundation
import AIKit

@MainActor
final class MemoryAnalyzerMonitor: ObservableObject {
    static let shared = MemoryAnalyzerMonitor()

    @Published private(set) var samples: [MemorySampleRecord] = []
    @Published private(set) var report: MemoryAnalysisReport?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var streamingAISummary = ""
    @Published private(set) var isStreamingAISummary = false
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var lastAIAnalysisAt: Date?
    @Published private(set) var aiProviderLabel = "Rule-based"
    @Published private(set) var isRunning = false
    @Published var memoryChatResponses: [AIChatMessage] = []
    @Published var memoryChatQuestion = ""
    @Published var isMemoryChatTyping = false

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
    private var memoryChatSessionID = UUID()
    private var memoryChatTask: Task<Void, Never>?

    private init() {
        analysisEngine = MemoryAnalysisEngine()
    }

    deinit {
        sampleTask?.cancel()
        analysisTask?.cancel()
        periodicAITask?.cancel()
        memoryChatTask?.cancel()
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

    func suggestedMemoryQuestions(for report: MemoryAnalysisReport) -> [String] {
        MemoryChatEngine.defaultQuestions(for: report)
    }

    func clearMemoryChat() {
        memoryChatTask?.cancel()
        memoryChatTask = nil
        memoryChatSessionID = UUID()
        memoryChatResponses = []
        memoryChatQuestion = ""
        isMemoryChatTyping = false
    }

    func askMemoryChat(question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let report else {
            memoryChatResponses.append(AIChatMessage(
                role: .assistant,
                text: "Collect a few memory samples first, then I can answer questions about your RAM usage."
            ))
            return
        }

        memoryChatQuestion = ""
        memoryChatResponses.append(AIChatMessage(role: .user, text: trimmed))

        let context = MemoryAnalysisContext(report: report, recentSamples: samples)
        let assistantID = UUID()
        let sessionID = memoryChatSessionID
        memoryChatResponses.append(AIChatMessage(id: assistantID, role: .assistant, text: "", isStreaming: true))
        isMemoryChatTyping = true

        memoryChatTask?.cancel()
        memoryChatTask = Task {
            let stream = analysisEngine.streamMemoryRespond(to: trimmed, context: context)
            var receivedContent = false

            do {
                for try await partial in stream {
                    guard !Task.isCancelled, sessionID == self.memoryChatSessionID else { return }
                    receivedContent = true
                    isMemoryChatTyping = false
                    updateMemoryAssistantMessage(id: assistantID, text: partial, isStreaming: true)
                }

                guard !Task.isCancelled, sessionID == self.memoryChatSessionID else { return }
                isMemoryChatTyping = false
                updateMemoryAssistantMessage(
                    id: assistantID,
                    text: memoryAssistantMessageText(id: assistantID),
                    isStreaming: false
                )
            } catch {
                guard !Task.isCancelled, sessionID == self.memoryChatSessionID else { return }
                let fallback = MemoryChatEngine.answer(question: trimmed, context: context)
                isMemoryChatTyping = false
                if receivedContent {
                    updateMemoryAssistantMessage(
                        id: assistantID,
                        text: memoryAssistantMessageText(id: assistantID),
                        isStreaming: false
                    )
                } else {
                    updateMemoryAssistantMessage(id: assistantID, text: fallback, isStreaming: false)
                }
            }
        }
    }

    private func memoryAssistantMessageText(id: UUID) -> String {
        memoryChatResponses.first(where: { $0.id == id })?.text ?? ""
    }

    private func updateMemoryAssistantMessage(id: UUID, text: String, isStreaming: Bool) {
        guard let index = memoryChatResponses.firstIndex(where: { $0.id == id }) else { return }
        memoryChatResponses[index].text = text
        memoryChatResponses[index].isStreaming = isStreaming
    }

    func releasePresentationMemory() {
        if !isAnalyzing && !isStreamingAISummary {
            streamingAISummary = report?.aiSummary ?? ""
        }
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
            isStreamingAISummary = true
            streamingAISummary = ""
            defer {
                isAnalyzing = false
                isStreamingAISummary = false
                samplesSinceLastAnalysis = 0
            }

            let status = await analysisEngine.providerStatus()
            aiProviderLabel = status.isGenerativeAvailable ? status.displayName : "Rule-based"

            let base = analysisEngine.prepareReport(from: samples)
            let context = MemoryAnalysisContext(report: base, recentSamples: samples)
            let fallback = analysisEngine.fallbackSummary(for: base)
            let stream = analysisEngine.streamMemorySummary(context: context, fallback: fallback)

            var finalSummary = ""
            do {
                for try await partial in stream {
                    guard !Task.isCancelled else { return }
                    finalSummary = partial
                    streamingAISummary = partial
                }
            } catch {
                guard !Task.isCancelled else { return }
                finalSummary = fallback
                streamingAISummary = fallback
            }

            guard !Task.isCancelled else { return }
            let trimmed = finalSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let aiSummary = trimmed.isEmpty ? fallback : trimmed
            let result = MemoryAnalysisReport(
                sampledAt: base.sampledAt,
                sampleCount: base.sampleCount,
                currentUsedPercent: base.currentUsedPercent,
                averageUsedPercent: base.averageUsedPercent,
                peakUsedPercent: base.peakUsedPercent,
                persistentConsumers: base.persistentConsumers,
                recommendations: base.recommendations,
                aiSummary: aiSummary
            )
            report = result
            streamingAISummary = aiSummary
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
