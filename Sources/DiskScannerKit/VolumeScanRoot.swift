import Foundation

public enum VolumeScanRoot {
    /// On modern macOS the boot volume mount (`/`) is a sealed system snapshot.
    /// User data and applications live on the Data volume.
    public static func effectiveScanRoot(for mountPath: URL, fileManager: FileManager = .default) -> URL {
        let path = mountPath.standardizedFileURL.path
        guard path == "/" else { return mountPath.standardizedFileURL }

        let dataRoot = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        if fileManager.fileExists(atPath: dataRoot.path) {
            return dataRoot
        }
        return mountPath.standardizedFileURL
    }
}
