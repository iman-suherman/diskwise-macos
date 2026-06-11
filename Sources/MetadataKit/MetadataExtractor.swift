import AVFoundation
import Foundation
import ImageIO
import DatabaseKit

public final class MetadataExtractor: @unchecked Sendable {
    public init() {}

    public func extract(for url: URL) -> ExtractedMetadata? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mkv", "mov", "avi", "m4v", "webm", "ts":
            return extractVideo(for: url)
        case "jpg", "jpeg", "png", "heic", "gif", "tif", "tiff":
            return extractImage(for: url)
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return extractArchive(for: url)
        default:
            return nil
        }
    }

    private func extractVideo(for url: URL) -> ExtractedMetadata? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration.seconds.isFinite ? asset.duration.seconds : nil

        var codec: String?
        var resolution: String?
        var bitrate: Int?

        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            resolution = "\(Int(abs(size.width)))x\(Int(abs(size.height)))"
            if let formatDescriptions = track.formatDescriptions as? [CMFormatDescription],
               let first = formatDescriptions.first {
                codec = CMFormatDescriptionGetMediaSubType(first).toString()
            }
            bitrate = Int(track.estimatedDataRate)
        }

        return ExtractedMetadata(
            filePath: url.path,
            payload: .video(
                VideoMetadata(duration: duration, codec: codec, resolution: resolution, bitrate: bitrate)
            )
        )
    }

    private func extractImage(for url: URL) -> ExtractedMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        var camera: String?

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            camera = exif[kCGImagePropertyExifLensModel] as? String
                ?? exif[kCGImagePropertyExifCameraOwnerName] as? String
        }

        return ExtractedMetadata(
            filePath: url.path,
            payload: .image(ImageMetadata(width: width, height: height, camera: camera))
        )
    }

    private func extractArchive(for url: URL) -> ExtractedMetadata? {
        ExtractedMetadata(
            filePath: url.path,
            payload: .archive(ArchiveMetadata(contentsCount: nil))
        )
    }
}

public final class MetadataEngine: @unchecked Sendable {
    private let extractor: MetadataExtractor
    private let database: DiskWiseDatabase

    public init(database: DiskWiseDatabase, extractor: MetadataExtractor = MetadataExtractor()) {
        self.database = database
        self.extractor = extractor
    }

    public func enrichFiles(_ files: [FileRecord]) throws {
        for file in files {
            guard let fileID = file.id else { continue }
            let url = URL(fileURLWithPath: file.path)
            guard let extracted = extractor.extract(for: url) else { continue }

            let (metadataType, payloadJSON) = try encode(extracted.payload)
            try database.insertMetadata(
                FileMetadataRecord(fileID: fileID, metadataType: metadataType, payloadJSON: payloadJSON)
            )
        }
    }

    private func encode(_ payload: MetadataPayload) throws -> (String, String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        switch payload {
        case .video(let metadata):
            return ("video", String(data: try encoder.encode(metadata), encoding: .utf8) ?? "{}")
        case .image(let metadata):
            return ("image", String(data: try encoder.encode(metadata), encoding: .utf8) ?? "{}")
        case .archive(let metadata):
            return ("archive", String(data: try encoder.encode(metadata), encoding: .utf8) ?? "{}")
        }
    }
}

private extension FourCharCode {
    func toString() -> String {
        String(format: "%c%c%c%c",
               (self >> 24) & 0xFF,
               (self >> 16) & 0xFF,
               (self >> 8) & 0xFF,
               self & 0xFF)
    }
}
