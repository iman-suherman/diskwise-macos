import Foundation

public struct VideoMetadata: Codable, Sendable {
    public let duration: Double?
    public let codec: String?
    public let resolution: String?
    public let bitrate: Int?

    public init(duration: Double?, codec: String?, resolution: String?, bitrate: Int?) {
        self.duration = duration
        self.codec = codec
        self.resolution = resolution
        self.bitrate = bitrate
    }
}

public struct ImageMetadata: Codable, Sendable {
    public let width: Int?
    public let height: Int?
    public let camera: String?

    public init(width: Int?, height: Int?, camera: String?) {
        self.width = width
        self.height = height
        self.camera = camera
    }
}

public struct ArchiveMetadata: Codable, Sendable {
    public let contentsCount: Int?

    public init(contentsCount: Int?) {
        self.contentsCount = contentsCount
    }
}

public enum MetadataPayload: Sendable {
    case video(VideoMetadata)
    case image(ImageMetadata)
    case archive(ArchiveMetadata)
}

public struct ExtractedMetadata: Sendable {
    public let filePath: String
    public let payload: MetadataPayload

    public init(filePath: String, payload: MetadataPayload) {
        self.filePath = filePath
        self.payload = payload
    }
}
