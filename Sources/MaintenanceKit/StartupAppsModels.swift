import Foundation

public enum StartupAppSource: String, Sendable, CaseIterable, Codable, Identifiable {
    case loginItem
    case dockPinned
    case launchAgent
    case backgroundItem

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .loginItem: return "Open at Login"
        case .dockPinned: return "Dock"
        case .launchAgent: return "Launch Agent"
        case .backgroundItem: return "Background Item"
        }
    }

    public var icon: String {
        switch self {
        case .loginItem: return "power.circle"
        case .dockPinned: return "dock.rectangle"
        case .launchAgent: return "gearshape.2"
        case .backgroundItem: return "arrow.triangle.2.circlepath"
        }
    }
}

public enum StartupAppRecommendation: String, Sendable, Codable {
    case keepAtLogin
    case disableAtLogin
    case optional

    public var displayName: String {
        switch self {
        case .keepAtLogin: return "Keep at login"
        case .disableAtLogin: return "Disable at login"
        case .optional: return "Optional"
        }
    }

    public var icon: String {
        switch self {
        case .keepAtLogin: return "checkmark.circle.fill"
        case .disableAtLogin: return "xmark.circle.fill"
        case .optional: return "questionmark.circle.fill"
        }
    }
}

public struct StartupAppItem: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let name: String
    public let path: String?
    public let bundleIdentifier: String?
    public let source: StartupAppSource
    public let isHidden: Bool
    public let detail: String
    public let alsoInDock: Bool
    public let alsoLoginItem: Bool

    public init(
        id: String? = nil,
        name: String,
        path: String?,
        bundleIdentifier: String? = nil,
        source: StartupAppSource,
        isHidden: Bool = false,
        detail: String = "",
        alsoInDock: Bool = false,
        alsoLoginItem: Bool = false
    ) {
        self.id = id ?? Self.makeID(name: name, path: path, source: source)
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.source = source
        self.isHidden = isHidden
        self.detail = detail
        self.alsoInDock = alsoInDock
        self.alsoLoginItem = alsoLoginItem
    }

    private static func makeID(name: String, path: String?, source: StartupAppSource) -> String {
        let pathPart = path ?? name
        return "\(source.rawValue)|\(pathPart)"
    }
}

public struct StartupAppAnalysis: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let itemID: String
    public let recommendation: StartupAppRecommendation
    public let analysis: String

    public init(itemID: String, recommendation: StartupAppRecommendation, analysis: String) {
        self.id = itemID
        self.itemID = itemID
        self.recommendation = recommendation
        self.analysis = analysis
    }
}

public struct StartupAppsScanResult: Sendable {
    public let scannedAt: Date
    public let items: [StartupAppItem]

    public init(scannedAt: Date = Date(), items: [StartupAppItem]) {
        self.scannedAt = scannedAt
        self.items = items
    }

    public var loginItemCount: Int {
        items.filter { $0.source == .loginItem }.count
    }

    public var dockPinnedCount: Int {
        items.filter { $0.source == .dockPinned }.count
    }

    public var launchAgentCount: Int {
        items.filter { $0.source == .launchAgent || $0.source == .backgroundItem }.count
    }
}
