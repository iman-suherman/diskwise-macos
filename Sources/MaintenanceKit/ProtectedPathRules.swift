import Foundation

public enum ProtectedPathRules {
    private static let blockedPrefixes = [
        "/System/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/cores/",
        "/dev/",
        "/etc/",
        "/var/db/",
        "/private/var/db/",
    ]

    private static let blockedFragments = [
        "/AssetsV2/",
        "com_apple_mobileasset",
        "/System/Library/",
        "/System/Volumes/Preboot/",
        "/Library/Updates/",
        "/private/var/folders/",
        "/Preboot/",
    ]

    public static func isBlockedPath(_ path: String) -> Bool {
        let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
        if blockedPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }
        let lower = normalized.lowercased()
        return blockedFragments.contains { lower.contains($0.lowercased()) }
    }

    public static func isUserHomePath(_ path: String, homeDirectory: String) -> Bool {
        let normalizedHome = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        let normalizedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        return normalizedPath == normalizedHome || normalizedPath.hasPrefix(normalizedHome + "/")
    }

    public static func isSafeCleanupPath(_ path: String, homeDirectory: String) -> Bool {
        guard !isBlockedPath(path) else { return false }
        guard isUserHomePath(path, homeDirectory: homeDirectory) || isUserApplicationsPath(path, homeDirectory: homeDirectory) else {
            return false
        }
        return true
    }

    public static func isUserApplicationsPath(_ path: String, homeDirectory: String) -> Bool {
        let userApps = (homeDirectory as NSString).appendingPathComponent("Applications")
        let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
        return normalized == userApps || normalized.hasPrefix(userApps + "/")
    }

    public static func isSystemApplicationsPath(_ path: String) -> Bool {
        path.hasPrefix("/Applications/") && !path.contains("/Users/")
    }
}
