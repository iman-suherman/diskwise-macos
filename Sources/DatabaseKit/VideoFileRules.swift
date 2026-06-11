import Foundation

public enum VideoFileRules {
    public static let extensions: Set<String> = [
        "mp4", "mkv", "mov", "avi", "m4v", "webm", "ts",
        "mpg", "mpeg", "3gp", "wmv", "flv", "ogv",
    ]

    /// True only when the filename ends with a known video extension (case-insensitive).
    public static func isVideoFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return extensions.contains(ext)
    }

    /// User-owned video files safe to surface in cleanup recommendations.
    public static func isArchivableOldVideo(_ path: String) -> Bool {
        isVideoFile(path) && RemovablePathRules.isUserAccessibleMedia(path)
    }
}
