import Foundation

/// Fills storage totals for directories that `FileManager` cannot fully enumerate
/// (permissions, TCC, sealed system paths) using `du` minus already-indexed bytes.
public enum StorageGapFill {
    private static let minimumGapBytes: Int64 = 1_048_576

    public static func appendGaps(
        scanRoot: URL,
        to results: inout [ScannedFile],
        fileManager: FileManager = .default,
        isCancelled: (@Sendable () -> Bool)? = nil,
        onProgress: (@Sendable (_ path: String, _ processed: Int, _ total: Int) -> Void)? = nil
    ) {
        let topLevelNames = (try? fileManager.contentsOfDirectory(atPath: scanRoot.path)) ?? []
        let topLevelChildren = topLevelNames.filter { !$0.hasPrefix(".") }

        for (index, name) in topLevelChildren.enumerated() {
            if isCancelled?() == true { return }
            let child = scanRoot.appendingPathComponent(name, isDirectory: true)
            appendGap(
                at: child,
                to: &results,
                fileManager: fileManager
            )
            onProgress?(child.path, index + 1, topLevelChildren.count)
        }

        let usersDirectory = scanRoot.appendingPathComponent("Users", isDirectory: true)
        guard fileManager.fileExists(atPath: usersDirectory.path) else { return }

        let userNames = (try? fileManager.contentsOfDirectory(atPath: usersDirectory.path)) ?? []
        let userChildren = userNames.filter { !$0.hasPrefix(".") }
        let usersTotal = userChildren.count

        for (index, name) in userChildren.enumerated() {
            if isCancelled?() == true { return }
            let userDirectory = usersDirectory.appendingPathComponent(name, isDirectory: true)
            appendGap(
                at: userDirectory,
                to: &results,
                fileManager: fileManager
            )
            onProgress?(userDirectory.path, index + 1, usersTotal)
        }
    }

    private static func appendGapsForImmediateChildren(
        of directory: URL,
        to results: inout [ScannedFile],
        fileManager: FileManager,
        isCancelled: (@Sendable () -> Bool)?
    ) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }

        for name in names where !name.hasPrefix(".") {
            if isCancelled?() == true { return }
            appendGap(
                at: directory.appendingPathComponent(name, isDirectory: true),
                to: &results,
                fileManager: fileManager
            )
        }
    }

    private static func appendGap(
        at directory: URL,
        to results: inout [ScannedFile],
        fileManager: FileManager
    ) {
        let directoryPath = directory.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        let diskUsage = FastDirectorySize.sizeOfDirectory(at: directoryPath, fileManager: fileManager)
        guard diskUsage > 0 else { return }

        let indexed = indexedBytes(under: directoryPath, in: results)
        let gap = diskUsage - indexed
        guard gap >= minimumGapBytes else { return }

        let values = try? directory.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
        ])

        results.append(
            ScannedFile(
                path: directoryPath,
                size: gap,
                createdAt: values?.creationDate,
                modifiedAt: values?.contentModificationDate,
                lastAccessed: values?.contentAccessDate,
                extensionName: nil,
                isDirectory: false
            )
        )
    }

    private static func indexedBytes(under directoryPath: String, in results: [ScannedFile]) -> Int64 {
        results.reduce(into: Int64(0)) { total, entry in
            guard !entry.isDirectory else { return }
            if entry.path == directoryPath || entry.path.hasPrefix(directoryPath + "/") {
                total += entry.size
            }
        }
    }
}
