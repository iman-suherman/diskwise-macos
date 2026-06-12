import Foundation

public enum FastDirectorySize {
    /// Returns on-disk usage for a directory, preferring `du` over per-file enumeration.
    public static func sizeOfDirectory(at path: String, fileManager: FileManager = .default) -> Int64 {
        if let bytes = diskUsageBytes(at: path) {
            return bytes
        }
        return enumeratedSize(at: path, fileManager: fileManager)
    }

    /// Uses `/usr/bin/du -sk`, equivalent to `du -sh` for total directory size.
    public static func diskUsageBytes(at path: String) -> Int64? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isWhitespace)
                .first,
                let kilobytes = Int64(output)
            else {
                return nil
            }
            return kilobytes * 1024
        } catch {
            return nil
        }
    }

    private static func enumeratedSize(at path: String, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
