import Foundation

/// Fast volume scans size most top-level folders with `du` and only enumerate user data.
public enum VolumeTieredScan {
    public static let drillTopLevelFolderName = "Users"

    public static func shouldUseTieredScan(
        at scanRoot: URL,
        mode: ScanMode,
        isFolderScan: Bool
    ) -> Bool {
        guard mode == .fast, !isFolderScan else { return false }
        return true
    }

    public static func shouldSummarizeTopLevelDirectory(named name: String) -> Bool {
        name != drillTopLevelFolderName
    }

    public static func isUnderUserLibrary(_ url: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        guard let usersIndex = components.firstIndex(of: "Users"),
              usersIndex + 2 < components.count,
              components[usersIndex + 2] == "Library" else {
            return false
        }
        return true
    }
}
