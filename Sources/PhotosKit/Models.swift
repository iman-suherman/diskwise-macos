import Foundation

public enum PhotosAuthorizationStatus: String, Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited

    public var canReadLibrary: Bool {
        switch self {
        case .authorized, .limited: return true
        case .notDetermined, .restricted, .denied: return false
        }
    }
}

public enum PhotoMediaType: String, Sendable, Codable, CaseIterable {
    case image
    case video
    case audio
    case unknown
}

public struct PhotoAssetRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let mediaType: PhotoMediaType
    public let byteSize: Int64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let durationSeconds: Double
    public let creationDate: Date?
    public let modificationDate: Date?
    public let isScreenshot: Bool
    public let isBurst: Bool
    public let isFavorite: Bool
    public let burstIdentifier: String?

    public init(
        id: String,
        mediaType: PhotoMediaType,
        byteSize: Int64,
        pixelWidth: Int,
        pixelHeight: Int,
        durationSeconds: Double = 0,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        isScreenshot: Bool = false,
        isBurst: Bool = false,
        isFavorite: Bool = false,
        burstIdentifier: String? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.byteSize = max(0, byteSize)
        self.pixelWidth = max(0, pixelWidth)
        self.pixelHeight = max(0, pixelHeight)
        self.durationSeconds = max(0, durationSeconds)
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isScreenshot = isScreenshot
        self.isBurst = isBurst
        self.isFavorite = isFavorite
        self.burstIdentifier = burstIdentifier
    }

    public var isVideo: Bool { mediaType == .video }

    public var exactFingerprint: String {
        let durationMs = Int((durationSeconds * 1000).rounded())
        return "\(mediaType.rawValue)_\(byteSize)_\(pixelWidth)x\(pixelHeight)_\(durationMs)"
    }
}

public enum PhotosClutterBucket: String, Sendable, CaseIterable, Identifiable, Codable {
    case exactDuplicates
    case similar
    case screenshots
    case bursts
    case largeVideos
    case oldMedia

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .exactDuplicates: return "Exact Duplicates"
        case .similar: return "Similar Media"
        case .screenshots: return "Screenshots"
        case .bursts: return "Burst Photos"
        case .largeVideos: return "Large Videos"
        case .oldMedia: return "Older Media"
        }
    }

    public var subtitle: String {
        switch self {
        case .exactDuplicates: return "Same size and dimensions — keep one copy"
        case .similar: return "Near-matches from the same day — review carefully"
        case .screenshots: return "Screen captures that often pile up"
        case .bursts: return "Extra frames from burst mode"
        case .largeVideos: return "Videos over 100 MB"
        case .oldMedia: return "Items older than two years"
        }
    }

    public var systemImage: String {
        switch self {
        case .exactDuplicates: return "doc.on.doc.fill"
        case .similar: return "rectangle.on.rectangle.angled"
        case .screenshots: return "camera.viewfinder"
        case .bursts: return "square.stack.3d.up.fill"
        case .largeVideos: return "film"
        case .oldMedia: return "calendar"
        }
    }
}

public struct PhotosDuplicateGroup: Identifiable, Sendable, Hashable {
    public let id: String
    public let fingerprint: String
    public let assets: [PhotoAssetRecord]
    public let totalSize: Int64
    public let reclaimableSize: Int64

    public init(id: String, fingerprint: String, assets: [PhotoAssetRecord]) {
        self.id = id
        self.fingerprint = fingerprint
        self.assets = assets
        self.totalSize = assets.reduce(0) { $0 + $1.byteSize }
        let sorted = assets.sorted { $0.byteSize > $1.byteSize }
        self.reclaimableSize = sorted.dropFirst().reduce(0) { $0 + $1.byteSize }
    }

    /// Keep favorites first, then largest; extras are cleanup candidates.
    public var suggestedKeepID: String {
        if let favorite = assets.first(where: \.isFavorite) {
            return favorite.id
        }
        return assets.max(by: { $0.byteSize < $1.byteSize })?.id ?? assets[0].id
    }

    public var suggestedCleanupIDs: [String] {
        let keep = suggestedKeepID
        return assets.map(\.id).filter { $0 != keep }
    }
}

public struct PhotosBucketSummary: Identifiable, Sendable, Hashable {
    public let bucket: PhotosClutterBucket
    public let assetIDs: [String]
    public let itemCount: Int
    public let reclaimableBytes: Int64

    public var id: String { bucket.id }

    public init(bucket: PhotosClutterBucket, assetIDs: [String], reclaimableBytes: Int64) {
        self.bucket = bucket
        self.assetIDs = assetIDs
        self.itemCount = assetIDs.count
        self.reclaimableBytes = max(0, reclaimableBytes)
    }
}

public struct PhotosRecommendation: Identifiable, Sendable, Hashable {
    public let id: String
    public let bucket: PhotosClutterBucket
    public let title: String
    public let detail: String
    public let estimatedSavings: Int64
    public let assetIDs: [String]

    public init(
        bucket: PhotosClutterBucket,
        title: String,
        detail: String,
        estimatedSavings: Int64,
        assetIDs: [String]
    ) {
        self.id = bucket.rawValue
        self.bucket = bucket
        self.title = title
        self.detail = detail
        self.estimatedSavings = max(0, estimatedSavings)
        self.assetIDs = assetIDs
    }
}

public struct PhotosLibraryReport: Sendable, Hashable {
    public let scannedAt: Date
    public let totalAssets: Int
    public let totalBytes: Int64
    public let buckets: [PhotosBucketSummary]
    public let exactDuplicateGroups: [PhotosDuplicateGroup]
    public let similarGroups: [PhotosDuplicateGroup]
    public let recommendations: [PhotosRecommendation]

    public var reclaimableBytes: Int64 {
        // Prefer recommendation totals (deduped by engine); fall back to bucket sum.
        if !recommendations.isEmpty {
            return recommendations.reduce(0) { $0 + $1.estimatedSavings }
        }
        return buckets.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public init(
        scannedAt: Date = Date(),
        totalAssets: Int,
        totalBytes: Int64,
        buckets: [PhotosBucketSummary],
        exactDuplicateGroups: [PhotosDuplicateGroup],
        similarGroups: [PhotosDuplicateGroup],
        recommendations: [PhotosRecommendation]
    ) {
        self.scannedAt = scannedAt
        self.totalAssets = totalAssets
        self.totalBytes = totalBytes
        self.buckets = buckets
        self.exactDuplicateGroups = exactDuplicateGroups
        self.similarGroups = similarGroups
        self.recommendations = recommendations
    }

    public static let empty = PhotosLibraryReport(
        totalAssets: 0,
        totalBytes: 0,
        buckets: [],
        exactDuplicateGroups: [],
        similarGroups: [],
        recommendations: []
    )
}

public struct PhotosScanProgress: Sendable, Equatable {
    public let phase: String
    public let processedCount: Int
    public let totalCount: Int

    public init(phase: String, processedCount: Int, totalCount: Int) {
        self.phase = phase
        self.processedCount = processedCount
        self.totalCount = totalCount
    }

    public var fraction: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, Double(processedCount) / Double(totalCount))
    }
}

public enum PhotosKitError: Error, LocalizedError, Sendable {
    case notAuthorized
    case userCancelled
    case cleanupFailed(String)
    case libraryUnavailable

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo Library access is required to scan and clean up."
        case .userCancelled:
            return "The operation was cancelled."
        case .cleanupFailed(let message):
            return message
        case .libraryUnavailable:
            return "The photo library is unavailable."
        }
    }
}
