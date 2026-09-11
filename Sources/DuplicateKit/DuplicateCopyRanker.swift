import Foundation
import DatabaseKit
import ImageIO

public enum DuplicateCopyRanker {
    public static func ranked(_ files: [FileRecord]) -> [FileRecord] {
        files.sorted { lhs, rhs in
            let left = score(lhs)
            let right = score(rhs)
            if left != right { return left > right }
            return lhs.path < rhs.path
        }
    }

    public static func suggestedKeep(in files: [FileRecord]) -> FileRecord? {
        ranked(files).first
    }

    public static func score(_ file: FileRecord) -> Int {
        var value = 20
        value += min(40, Int(file.size / 150_000))

        let name = URL(fileURLWithPath: file.path).lastPathComponent.lowercased()
        if name.contains("copy") || name.contains(" duplicate") {
            value -= 18
        }
        if name.contains("(") && name.contains(")") {
            value -= 10
        }
        if ScreenshotRules.isScreenshot(path: file.path) {
            value -= 8
        }
        if let pixels = imagePixelCount(at: file.path) {
            value += min(50, pixels / 250_000)
        }
        return value
    }

    private static func imagePixelCount(at path: String) -> Int? {
        guard ImageFileRules.isImageFile(path) else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return max(0, width) * max(0, height)
    }
}
