import Foundation

public struct MemoryProcessProfile: Identifiable, Sendable, Codable, Equatable {
    public let name: String
    public let averageMemoryBytes: Int64
    public let peakMemoryBytes: Int64
    public let sampleCount: Int

    public var id: String { name }

    public init(name: String, averageMemoryBytes: Int64, peakMemoryBytes: Int64, sampleCount: Int) {
        self.name = name
        self.averageMemoryBytes = averageMemoryBytes
        self.peakMemoryBytes = peakMemoryBytes
        self.sampleCount = sampleCount
    }
}

public enum MemoryActionKind: String, Sendable, Codable {
    case quitProcess
    case freeMemory
    case restartApp
    case reduceTabs
    case informational
}

public struct MemoryActionRecommendation: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let actionKind: MemoryActionKind
    public let targetProcessName: String?
    public let priority: Int

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        actionKind: MemoryActionKind,
        targetProcessName: String? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.actionKind = actionKind
        self.targetProcessName = targetProcessName
        self.priority = priority
    }
}

public struct MemorySampleRecord: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let usedPercent: Double
    public let usedBytes: Int64
    public let physicalBytes: Int64
    public let topProcesses: [MemoryProcessSample]

    public init(
        timestamp: Date,
        usedPercent: Double,
        usedBytes: Int64,
        physicalBytes: Int64,
        topProcesses: [MemoryProcessSample]
    ) {
        self.timestamp = timestamp
        self.usedPercent = usedPercent
        self.usedBytes = usedBytes
        self.physicalBytes = physicalBytes
        self.topProcesses = topProcesses
    }
}

public struct MemoryProcessSample: Sendable, Codable, Equatable {
    public let name: String
    public let memoryBytes: Int64

    public init(name: String, memoryBytes: Int64) {
        self.name = name
        self.memoryBytes = memoryBytes
    }
}

public struct MemoryAnalysisReport: Sendable, Codable, Equatable {
    public let sampledAt: Date
    public let sampleCount: Int
    public let currentUsedPercent: Double
    public let averageUsedPercent: Double
    public let peakUsedPercent: Double
    public let persistentConsumers: [MemoryProcessProfile]
    public let recommendations: [MemoryActionRecommendation]
    public let aiSummary: String?

    public init(
        sampledAt: Date,
        sampleCount: Int,
        currentUsedPercent: Double,
        averageUsedPercent: Double,
        peakUsedPercent: Double,
        persistentConsumers: [MemoryProcessProfile],
        recommendations: [MemoryActionRecommendation],
        aiSummary: String? = nil
    ) {
        self.sampledAt = sampledAt
        self.sampleCount = sampleCount
        self.currentUsedPercent = currentUsedPercent
        self.averageUsedPercent = averageUsedPercent
        self.peakUsedPercent = peakUsedPercent
        self.persistentConsumers = persistentConsumers
        self.recommendations = recommendations
        self.aiSummary = aiSummary
    }
}

public struct MemoryAnalysisContext: Sendable {
    public let report: MemoryAnalysisReport
    public let recentSamples: [MemorySampleRecord]

    public init(report: MemoryAnalysisReport, recentSamples: [MemorySampleRecord]) {
        self.report = report
        self.recentSamples = recentSamples
    }
}
