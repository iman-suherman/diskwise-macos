import Foundation

public enum DirectorySizeCalculator {
    public static func sizeOfItem(at path: String, fileManager: FileManager = .default) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            let attributes = try? fileManager.attributesOfItem(atPath: path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }

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

    public static func modificationDate(at path: String, fileManager: FileManager = .default) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    public static func isRecent(at path: String, days: Int = 7, fileManager: FileManager = .default) -> Bool {
        guard let modified = modificationDate(at: path, fileManager: fileManager) else { return false }
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        return modified > threshold
    }
}
