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

    /// Expands a drill root into independently scannable directories for sequential indexing.
    public static func sequentialDrillDirectories(
        at drillRoot: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let standardized = drillRoot.standardizedFileURL
        if standardized.lastPathComponent == drillTopLevelFolderName {
            return expandUserHomes(at: standardized, fileManager: fileManager)
        }
        return expandImmediateChildDirectories(at: standardized, fileManager: fileManager, fallback: standardized)
    }

    private static func expandUserHomes(at usersURL: URL, fileManager: FileManager) -> [URL] {
        guard let userNames = try? fileManager.contentsOfDirectory(atPath: usersURL.path) else {
            return [usersURL]
        }

        var tasks: [URL] = []
        for userName in userNames.sorted() where !userName.hasPrefix(".") {
            let home = usersURL.appendingPathComponent(userName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: home.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            let childTasks = expandImmediateChildDirectories(
                at: home,
                fileManager: fileManager,
                fallback: home
            )
            tasks.append(contentsOf: childTasks)
        }

        return tasks.isEmpty ? [usersURL] : tasks
    }

    private static func expandImmediateChildDirectories(
        at directory: URL,
        fileManager: FileManager,
        fallback: URL
    ) -> [URL] {
        guard let childNames = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return [fallback]
        }

        let childDirectories = childNames.sorted().compactMap { childName -> URL? in
            guard !childName.hasPrefix(".") else { return nil }
            let childURL = directory.appendingPathComponent(childName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            return childURL
        }

        return childDirectories.isEmpty ? [fallback] : childDirectories
    }
}
