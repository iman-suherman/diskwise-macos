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
            return "Sizes system folders in one step, then indexes your user files — usually under 5 minutes."
        case .deep:
            return "Indexes every file individually — typically 10–25 minutes on large drives."
        }
    }

    /// Shown under the scanner log while a deep scan is running.
    public var scanningLogExplanation: String {
        switch self {
        case .fast:
            return ""
        case .deep:
            return """
            Deep scan walks every file and folder on this volume to build an exact size map instead of estimating system directories. \
            DiskWise records individual paths and sizes so storage breakdown and unmapped-space coverage are more complete. \
            Protected macOS locations are included where Full Disk Access allows. Expect 10–25 minutes on large drives; live progress is written to the log above.
            """
        }
    }
}
