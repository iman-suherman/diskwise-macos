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

    /// Heavy macOS user Library folders that are safe to size in one step during fast scans.
    public static let userLibraryBulkFolderNames: Set<String> = [
        "Containers",
        "Caches",
        "Group Containers",
        "Logs",
        "Saved Application State",
        "HTTPStorages",
        "WebKit",
        "Developer",
        "Mail",
        "Messages",
        "Safari",
        "Metadata",
        "Biome",
        "Daemon Containers",
        "Application Scripts",
        "CloudStorage",
        "CoreFollowUp",
        "Preferences",
        "Spelling",
        "Translation",
        "UnifiedAssetFramework",
    ]

    public static func matchesVisibleDirectory(named name: String) -> Bool {
        visibleFolderNames.contains(name)
    }

    public static func matchesHiddenDirectory(named name: String) -> Bool {
        hiddenFolderNames.contains(name)
    }

    public static func shouldSummarizeDirectory(named name: String, mode: ScanMode) -> Bool {
        guard mode == .fast else { return false }
        return matchesVisibleDirectory(named: name)
            || name == ".git"
            || userLibraryBulkFolderNames.contains(name)
    }

    public static func shouldSummarizeDirectory(at url: URL, named name: String, mode: ScanMode) -> Bool {
        if shouldSummarizeDirectory(named: name, mode: mode) {
            return true
        }
        guard mode == .fast, VolumeTieredScan.isUnderUserLibrary(url) else { return false }
        return userLibraryBulkFolderNames.contains(name)
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
