import Foundation

public enum DMGSafetyLevel: String, Sendable {
    case safeInstaller
    case cautionOSImage
    case appleDownloadArtifact
}

public struct DMGFileClassification: Sendable {
    public let level: DMGSafetyLevel
    public let label: String
    public let detail: String
    public let selectedByDefault: Bool

    public init(level: DMGSafetyLevel, label: String, detail: String, selectedByDefault: Bool) {
        self.level = level
        self.label = label
        self.detail = detail
        self.selectedByDefault = selectedByDefault
    }
}

public enum RemovablePathRules {
    private static let cautionOSNameFragments = [
        "os.dmg",
        "os.clone.dmg",
        "macos",
        "install macos",
        "recovery",
    ]

    /// User-folder installer leftovers: `.dmg`, Apple download artifacts, etc.
    /// Excludes macOS MobileAsset images under `/System/Library/AssetsV2/`.
    public static func isUserManagedInstallerArtifact(_ path: String) -> Bool {
        let normalized = path.lowercased()
        guard isInstallerArtifactName(normalized) else { return false }
        guard !isBlockedSystemPath(normalized) else { return false }
        return isUserAccessiblePath(normalized)
    }

    public static func isUserManagedDMG(_ path: String) -> Bool {
        isUserManagedInstallerArtifact(path) && path.lowercased().hasSuffix(".dmg")
    }

    public static func classifyInstallerArtifact(path: String, size: Int64) -> DMGFileClassification? {
        guard isUserManagedInstallerArtifact(path) else { return nil }

        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()

        if isCautionOSImage(name: name, size: size) {
            return DMGFileClassification(
                level: .cautionOSImage,
                label: "Review carefully",
                detail: "May be a macOS installer, clone, or backup image. Delete only if you no longer need it.",
                selectedByDefault: false
            )
        }

        if isAppleDownloadArtifact(name) {
            return DMGFileClassification(
                level: .appleDownloadArtifact,
                label: "Update download file",
                detail: "Related Apple download data. Usually safe after the update finished when stored in Downloads or Desktop.",
                selectedByDefault: true
            )
        }

        return DMGFileClassification(
            level: .safeInstaller,
            label: "Safe to remove",
            detail: "Leftover installer image — safe to delete after the app is already installed.",
            selectedByDefault: true
        )
    }

    private static func isInstallerArtifactName(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if name.hasSuffix(".dmg") { return true }
        if name.hasSuffix(".dmg.aea") { return true }
        if name.hasSuffix(".trustcache") { return true }
        if name.hasSuffix(".integrity_catalog") { return true }
        return false
    }

    private static func isCautionOSImage(name: String, size: Int64) -> Bool {
        if name == "os.dmg" || name == "os.clone.dmg" {
            return true
        }
        let largeImageThreshold: Int64 = 2_000_000_000
        guard size >= largeImageThreshold, name.hasSuffix(".dmg") else { return false }
        return cautionOSNameFragments.contains { name.contains($0) }
    }

    private static func isAppleDownloadArtifact(_ name: String) -> Bool {
        name.hasSuffix(".dmg.aea")
            || name.hasSuffix(".trustcache")
            || name.hasSuffix(".integrity_catalog")
    }

    private static func isBlockedSystemPath(_ path: String) -> Bool {
        let blockedPrefixes = [
            "/system/",
            "/usr/",
            "/bin/",
            "/sbin/",
            "/cores/",
            "/dev/",
            "/etc/",
            "/var/db/",
        ]
        if blockedPrefixes.contains(where: { path.hasPrefix($0) }) {
            return true
        }

        let blockedFragments = [
            "/assetsv2/",
            "com_apple_mobileasset",
            "/system/library/",
            "/system/volumes/preboot/",
            "/library/updates/",
            "/private/var/folders/",
            "/preboot/",
        ]
        return blockedFragments.contains(where: { path.contains($0) })
    }

    private static let userCleanupFolderFragments = [
        "/downloads/",
        "/desktop/",
        "/documents/",
    ]

    /// Only folders users normally manage manually — never Preboot, system volumes, or app bundles.
    private static func isUserAccessiblePath(_ path: String) -> Bool {
        guard path.contains("/users/") else { return false }
        return userCleanupFolderFragments.contains { path.contains($0) }
    }

    /// Media files stored under a user home directory — excludes system assets and Preboot.
    public static func isUserAccessibleMedia(_ path: String) -> Bool {
        let normalized = path.lowercased()
        guard !isBlockedSystemPath(normalized) else { return false }
        return normalized.contains("/users/")
    }
}
