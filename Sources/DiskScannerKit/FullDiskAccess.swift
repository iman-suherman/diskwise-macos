import Foundation
import System

public enum FullDiskAccess {
    private static let tccDirectory = "/Library/Application Support/com.apple.TCC"
    private static let tccDatabase = "\(tccDirectory)/TCC.db"
    private static let stocksContainer = NSHomeDirectory() + "/Library/Containers/com.apple.stocks"

    /// Returns true when the app can read macOS TCC protected paths (Full Disk Access granted).
    public static func hasFullDiskAccess(fileManager: FileManager = .default) -> Bool {
        if (try? fileManager.contentsOfDirectory(atPath: stocksContainer)) != nil {
            return true
        }

        if fileManager.isReadableFile(atPath: tccDatabase) {
            return true
        }

        if let contents = try? fileManager.contentsOfDirectory(atPath: tccDirectory), !contents.isEmpty {
            return true
        }

        return false
    }

    /// True when the app is running from Xcode DerivedData and may not auto-appear in the FDA list.
    public static var requiresManualRegistration: Bool {
        Bundle.main.bundlePath.contains("DerivedData")
    }

    /// Triggers protected-resource access attempts so macOS registers DiskWise in Full Disk Access.
    /// Opening protected files (not just `access(2)`) is required for the app to appear in the list.
    public static func registerForFullDiskAccess(fileManager: FileManager = .default) {
        if let fd = try? FileDescriptor.open(tccDatabase, .readOnly) {
            try? fd.close()
        }

        let protectedPaths = [
            stocksContainer,
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Messages",
            NSHomeDirectory() + "/Library/Safari",
            "/Library/Mail",
        ]

        for path in protectedPaths {
            _ = try? fileManager.contentsOfDirectory(atPath: path)
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
