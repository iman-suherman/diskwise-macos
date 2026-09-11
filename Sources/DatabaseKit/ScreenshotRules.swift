import Foundation

public enum ScreenshotRules {
    public static let subcategory = "screenshot"

    public static func isScreenshot(path: String) -> Bool {
        guard ImageFileRules.isImageFile(path) else { return false }

        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent.lowercased()
        let pathLower = path.lowercased()

        if name.contains("screenshot") || name.contains("screen shot") || name.contains("screen-shot") {
            return true
        }
        if name.contains("tangkapan layar") || name.contains("captura de pantalla") {
            return true
        }
        if name.hasPrefix("cleanshot") || name.hasPrefix("clean shot") {
            return true
        }
        if pathLower.contains("/screenshots/") || pathLower.contains("/screenshot/") {
            return true
        }
        return false
    }

    public static func subcategory(for path: String) -> String? {
        isScreenshot(path: path) ? subcategory : nil
    }
}

public extension FileRecord {
    var isScreenshot: Bool {
        subcategory == ScreenshotRules.subcategory || ScreenshotRules.isScreenshot(path: path)
    }
}
