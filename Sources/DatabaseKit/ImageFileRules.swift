import Foundation

public enum ImageFileRules {
    public static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp",
    ]

    public static func isImageFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        return extensions.contains(ext)
    }
}

public extension FileRecord {
    var isImageFile: Bool {
        category == .photo || ImageFileRules.isImageFile(path)
    }

    var isVideoFile: Bool {
        category == .video || VideoFileRules.isVideoFile(path)
    }

    var isPreviewableMedia: Bool {
        isImageFile || isVideoFile
    }
}
