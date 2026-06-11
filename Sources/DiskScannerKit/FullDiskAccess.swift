import Foundation

public enum FullDiskAccess {
    private static let tccDirectory = "/Library/Application Support/com.apple.TCC"
    private static let tccDatabase = "\(tccDirectory)/TCC.db"

    /// Returns true when the app can read macOS TCC protected paths (Full Disk Access granted).
    public static func hasFullDiskAccess(fileManager: FileManager = .default) -> Bool {
        if fileManager.isReadableFile(atPath: tccDatabase) {
            return true
        }

        if let contents = try? fileManager.contentsOfDirectory(atPath: tccDirectory), !contents.isEmpty {
            return true
        }

        return false
    }

    /// Triggers protected-resource access attempts so macOS can register DiskWise in Full Disk Access.
    /// Note: locally built debug apps usually still need to be added manually with the + button.
    public static func registerForFullDiskAccess(fileManager: FileManager = .default) {
        let protectedPaths = [
            tccDatabase,
            tccDirectory,
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Messages",
            NSHomeDirectory() + "/Library/Safari",
            "/Library/Mail",
        ]

        for path in protectedPaths {
            _ = try? fileManager.contentsOfDirectory(atPath: path)
            _ = fileManager.isReadableFile(atPath: path)
        }
    }

    /// Path to the running app bundle (shown when users must add DiskWise manually).
    public static var appBundlePath: String {
        Bundle.main.bundleURL.path
    }

    /// True when volume discovery suggests drives are hidden without Full Disk Access.
    public static func likelyNeedsFullDiskAccess(fileManager: FileManager = .default) -> Bool {
        VolumeDiscovery.likelyNeedsFullDiskAccess(fileManager: fileManager)
    }

    /// True when the app should prompt the user to grant Full Disk Access.
    public static func shouldPromptForAccess(
        hasSeenPrompt: Bool,
        fileManager: FileManager = .default
    ) -> Bool {
        guard !hasFullDiskAccess(fileManager: fileManager) else { return false }
        return !hasSeenPrompt || likelyNeedsFullDiskAccess(fileManager: fileManager)
    }
}
