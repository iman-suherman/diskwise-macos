import Foundation

/// Controls how Step 1 indexes the filesystem.
public enum ScanMode: String, Sendable, CaseIterable, Identifiable {
    case fast
    case deep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fast: return "Fast"
        case .deep: return "Deep"
        }
    }

    public var detail: String {
        switch self {
        case .fast:
            return "Sizes dependency folders in one step — usually under 5 minutes."
        case .deep:
            return "Indexes every file individually — typically 10–25 minutes on large drives."
        }
    }
}
