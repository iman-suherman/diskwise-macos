import Foundation

/// macOS bundles (.app, .framework, …) are skipped by `FileManager` enumeration.
/// Size them with `du` so they contribute to storage totals.
public enum PackageBundlePatterns {
    public static let packageExtensions: Set<String> = [
        "app",
        "framework",
        "plugin",
        "kext",
        "bundle",
        "xpc",
        "appex",
        "photoslibrary",
        "sparsebundle",
        "mlmodelc",
    ]

    public static func shouldSummarizePackage(at url: URL, isPackage: Bool?) -> Bool {
        if isPackage == true {
            return true
        }
        let ext = url.pathExtension.lowercased()
        return packageExtensions.contains(ext)
    }
}
