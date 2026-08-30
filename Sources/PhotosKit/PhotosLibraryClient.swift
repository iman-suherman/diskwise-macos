import Foundation

#if canImport(Photos)
import Photos
#endif

public protocol PhotosLibraryAccessing: Sendable {
    func authorizationStatus() -> PhotosAuthorizationStatus
    func requestAuthorization() async -> PhotosAuthorizationStatus
    func fetchAssets(
        progress: (@Sendable (PhotosScanProgress) -> Void)?
    ) async throws -> [PhotoAssetRecord]
    func deleteAssets(withIDs ids: [String]) async throws -> Int
}

#if canImport(Photos)
public struct PhotosLibraryClient: PhotosLibraryAccessing {
    public init() {}

    public func authorizationStatus() -> PhotosAuthorizationStatus {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestAuthorization() async -> PhotosAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: Self.map(status))
            }
        }
    }

    public func fetchAssets(
        progress: (@Sendable (PhotosScanProgress) -> Void)? = nil
    ) async throws -> [PhotoAssetRecord] {
        let status = authorizationStatus()
        guard status.canReadLibrary else { throw PhotosKitError.notAuthorized }

        return try await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.includeHiddenAssets = false
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: options)
            let total = result.count
            var records: [PhotoAssetRecord] = []
            records.reserveCapacity(total)

            result.enumerateObjects { asset, index, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }
                records.append(Self.record(from: asset))
                if index == 0 || index % 250 == 0 || index == total - 1 {
                    progress?(
                        PhotosScanProgress(
                            phase: "Indexing library",
                            processedCount: index + 1,
                            totalCount: total
                        )
                    )
                }
            }

            if Task.isCancelled { throw PhotosKitError.userCancelled }
            return records
        }.value
    }

    public func deleteAssets(withIDs ids: [String]) async throws -> Int {
        let status = authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw PhotosKitError.notAuthorized
        }
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return 0 }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: unique, options: nil)
        guard assets.count > 0 else { return 0 }

        return try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: PhotosKitError.cleanupFailed(error.localizedDescription))
                    return
                }
                guard success else {
                    continuation.resume(throwing: PhotosKitError.cleanupFailed("Photos could not move items to Recently Deleted."))
                    return
                }
                continuation.resume(returning: assets.count)
            })
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotosAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    private static func record(from asset: PHAsset) -> PhotoAssetRecord {
        let resources = PHAssetResource.assetResources(for: asset)
        let byteSize = resources.compactMap { resource -> Int64? in
            guard let value = resource.value(forKey: "fileSize") else { return nil }
            if let number = value as? NSNumber {
                return number.int64Value
            }
            if let intValue = value as? Int64 { return intValue }
            if let intValue = value as? Int { return Int64(intValue) }
            return nil
        }.max() ?? 0

        let mediaType: PhotoMediaType
        switch asset.mediaType {
        case .image: mediaType = .image
        case .video: mediaType = .video
        case .audio: mediaType = .audio
        case .unknown: mediaType = .unknown
        @unknown default: mediaType = .unknown
        }

        let subtypes = asset.mediaSubtypes
        let isScreenshot = subtypes.contains(.photoScreenshot)
        #if os(iOS) || os(tvOS) || os(macOS)
        let isBurst = asset.representsBurst || asset.burstIdentifier != nil
        #else
        let isBurst = asset.burstIdentifier != nil
        #endif

        return PhotoAssetRecord(
            id: asset.localIdentifier,
            mediaType: mediaType,
            byteSize: byteSize,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            durationSeconds: asset.duration,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            isScreenshot: isScreenshot,
            isBurst: isBurst,
            isFavorite: asset.isFavorite,
            burstIdentifier: asset.burstIdentifier
        )
    }
}
#else
/// Stub client for platforms without the Photos framework (e.g. pure SPM host tests).
public struct PhotosLibraryClient: PhotosLibraryAccessing {
    public init() {}

    public func authorizationStatus() -> PhotosAuthorizationStatus { .denied }

    public func requestAuthorization() async -> PhotosAuthorizationStatus { .denied }

    public func fetchAssets(
        progress: (@Sendable (PhotosScanProgress) -> Void)?
    ) async throws -> [PhotoAssetRecord] {
        throw PhotosKitError.libraryUnavailable
    }

    public func deleteAssets(withIDs ids: [String]) async throws -> Int {
        throw PhotosKitError.libraryUnavailable
    }
}
#endif

public struct PhotosCleanupEngine: Sendable {
    private let library: any PhotosLibraryAccessing

    public init(library: any PhotosLibraryAccessing = PhotosLibraryClient()) {
        self.library = library
    }

    /// Moves assets to Recently Deleted. Never permanently purges.
    public func moveToRecentlyDeleted(ids: [String]) async throws -> Int {
        try await library.deleteAssets(withIDs: ids)
    }
}

public struct PhotosConsultantService: Sendable {
    private let library: any PhotosLibraryAccessing
    private let insightEngine: PhotosInsightEngine

    public init(
        library: any PhotosLibraryAccessing = PhotosLibraryClient(),
        insightEngine: PhotosInsightEngine = PhotosInsightEngine()
    ) {
        self.library = library
        self.insightEngine = insightEngine
    }

    public func authorizationStatus() -> PhotosAuthorizationStatus {
        library.authorizationStatus()
    }

    public func requestAuthorization() async -> PhotosAuthorizationStatus {
        await library.requestAuthorization()
    }

    public func scan(
        progress: (@Sendable (PhotosScanProgress) -> Void)? = nil
    ) async throws -> (assets: [PhotoAssetRecord], report: PhotosLibraryReport) {
        progress?(PhotosScanProgress(phase: "Preparing", processedCount: 0, totalCount: 1))
        let assets = try await library.fetchAssets(progress: progress)
        progress?(
            PhotosScanProgress(
                phase: "Analyzing",
                processedCount: assets.count,
                totalCount: max(assets.count, 1)
            )
        )
        let report = insightEngine.analyze(assets)
        return (assets, report)
    }
}

public enum ByteCountFormat {
    public static func string(for bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
