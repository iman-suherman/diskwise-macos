import Foundation

/// Folder names where users delete the whole directory, never individual files inside.
/// In fast scan mode these are sized with `du` instead of enumerating every file.
public enum DirectorySizeOnlyPatterns {
    public static let visibleFolderNames: Set<String> = [
        "node_modules",
        "vendor",
        "venv",
        "Pods",
        "bower_components",
        "target",
        "build",
        "dist",
        "DerivedData",
    ]

    public static let hiddenFolderNames: Set<String> = [
        ".venv",
        "__pycache__",
        ".next",
        ".turbo",
        ".build",
        ".gradle",
    ]

    public static func matchesVisibleDirectory(named name: String) -> Bool {
        visibleFolderNames.contains(name)
    }

    public static func matchesHiddenDirectory(named name: String) -> Bool {
        hiddenFolderNames.contains(name)
    }

    public static func shouldSummarizeDirectory(named name: String, mode: ScanMode) -> Bool {
        guard mode == .fast else { return false }
        return matchesVisibleDirectory(named: name) || name == ".git"
    }

    /// Hidden bulk folders are not returned by `FileManager` when `.skipsHiddenFiles` is set,
    /// so callers probe for them explicitly under likely project directories.
    public static func shouldProbeForHiddenDirectories(at url: URL, mode: ScanMode) -> Bool {
        guard mode == .fast else { return false }

        let path = url.path
        if path.hasPrefix("/System")
            || path.hasPrefix("/Library")
            || path.hasPrefix("/Applications")
            || path.hasPrefix("/private/var")
        {
            return false
        }
        if path.contains("/node_modules/") || path.contains("/vendor/") || path.contains("/Pods/") {
            return false
        }
        return true
    }
}
