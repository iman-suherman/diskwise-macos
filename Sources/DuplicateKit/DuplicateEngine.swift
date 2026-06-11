import AVFoundation
import CryptoKit
import Foundation
import DatabaseKit
import MetadataKit

public enum DuplicateDetectionLevel: Int, Sendable, CaseIterable {
    case filename = 1
    case size = 2
    case hash = 3
    case videoFingerprint = 4

    public var label: String {
        switch self {
        case .filename: return "Matching filenames"
        case .size: return "Matching file sizes"
        case .hash: return "Computing file hashes"
        case .videoFingerprint: return "Fingerprinting videos"
        }
    }

    public var detail: String {
        switch self {
        case .filename: return "Grouping files with similar names"
        case .size: return "Finding files with identical sizes"
        case .hash: return "Reading file contents to confirm duplicates"
        case .videoFingerprint: return "Sampling video frames — this can take a while"
        }
    }
}

public struct DuplicateScanProgress: Sendable {
    public let level: DuplicateDetectionLevel
    public let levelIndex: Int
    public let levelCount: Int
    public let processedCount: Int
    public let totalCount: Int
    public let currentPath: String
    public let groupsFoundSoFar: Int

    public init(
        level: DuplicateDetectionLevel,
        levelIndex: Int,
        levelCount: Int,
        processedCount: Int,
        totalCount: Int,
        currentPath: String,
        groupsFoundSoFar: Int
    ) {
        self.level = level
        self.levelIndex = levelIndex
        self.levelCount = levelCount
        self.processedCount = processedCount
        self.totalCount = totalCount
        self.currentPath = currentPath
        self.groupsFoundSoFar = groupsFoundSoFar
    }

    public var levelFraction: Double {
        guard totalCount > 0 else { return levelIndex == levelCount - 1 ? 1 : 0 }
        return Double(processedCount) / Double(totalCount)
    }

    public var overallFraction: Double {
        guard levelCount > 0 else { return 0 }
        let completedLevels = Double(levelIndex)
        return min(1.0, (completedLevels + levelFraction) / Double(levelCount))
    }
}

public struct DuplicateGroup: Identifiable, Sendable {
    public let id: Int64
    public let level: DuplicateDetectionLevel
    public let fingerprint: String
    public let totalSize: Int64
    public let reclaimableSize: Int64
    public let files: [FileRecord]

    public init(
        id: Int64,
        level: DuplicateDetectionLevel,
        fingerprint: String,
        totalSize: Int64,
        reclaimableSize: Int64,
        files: [FileRecord]
    ) {
        self.id = id
        self.level = level
        self.fingerprint = fingerprint
        self.totalSize = totalSize
        self.reclaimableSize = reclaimableSize
        self.files = files
    }
}

public struct DuplicateScanSummary: Sendable {
    public let groupsFound: Int
    public let reclaimableBytes: Int64

    public init(groupsFound: Int, reclaimableBytes: Int64) {
        self.groupsFound = groupsFound
        self.reclaimableBytes = reclaimableBytes
    }
}

public final class DuplicateDetector: @unchecked Sendable {
    private let metadataExtractor: MetadataExtractor

    public init(metadataExtractor: MetadataExtractor = MetadataExtractor()) {
        self.metadataExtractor = metadataExtractor
    }

    public func sha256(for url: URL, chunkSize: Int = 1_048_576) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func normalizedFilename(_ path: String) -> String {
        let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
        let stripped = base
            .replacingOccurrences(of: #"\(\d+\)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" copy$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped
    }

    public func videoFingerprint(for url: URL) -> String? {
        guard let metadata = metadataExtractor.extract(for: url),
              case .video(let video) = metadata.payload else {
            return nil
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)

        var frameHashes: [String] = []
        let duration = asset.duration.seconds
        let sampleTimes: [Double] = duration.isFinite && duration > 0
            ? [0.1, duration * 0.5, max(duration - 0.2, 0.2)]
            : [0.1]

        for seconds in sampleTimes {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                frameHashes.append(hash(image: image))
            }
        }

        let signature = [
            video.resolution ?? "unknown",
            String(format: "%.2f", video.duration ?? 0),
            frameHashes.joined(separator: "|"),
        ].joined(separator: "::")

        return SHA256.hash(data: Data(signature.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    private func hash(image: CGImage) -> String {
        let width = min(image.width, 8)
        let height = min(image.height, 8)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return "invalid"
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return "invalid" }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let bytes = (0..<(width * height * 4)).map { buffer[$0] }
        return SHA256.hash(data: Data(bytes)).compactMap { String(format: "%02x", $0) }.joined()
    }
}

public final class DuplicateEngine: @unchecked Sendable {
    private let database: DiskWiseDatabase
    private let detector: DuplicateDetector

    public init(database: DiskWiseDatabase, detector: DuplicateDetector = DuplicateDetector()) {
        self.database = database
        self.detector = detector
    }

    public func detectAll(
        forDiskID diskID: Int64,
        levels: [DuplicateDetectionLevel] = DuplicateDetectionLevel.allCases,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> DuplicateScanSummary {
        let files = try database.files(forDiskID: diskID, limit: 100_000)
        var groupsFound = 0
        var reclaimableBytes: Int64 = 0
        let activeLevels = levels.filter { level in DuplicateDetectionLevel.allCases.contains(level) }

        for (levelIndex, level) in activeLevels.enumerated() {
            if isCancelled?() == true {
                throw CancellationError()
            }

            let summary: DuplicateScanSummary
            switch level {
            case .filename:
                summary = try detectByFilename(
                    files,
                    levelIndex: levelIndex,
                    levelCount: activeLevels.count,
                    groupsFoundSoFar: groupsFound,
                    onProgress: onProgress,
                    isCancelled: isCancelled
                )
            case .size:
                summary = try detectBySize(
                    files,
                    levelIndex: levelIndex,
                    levelCount: activeLevels.count,
                    groupsFoundSoFar: groupsFound,
                    onProgress: onProgress,
                    isCancelled: isCancelled
                )
            case .hash:
                summary = try detectByHash(
                    files,
                    levelIndex: levelIndex,
                    levelCount: activeLevels.count,
                    groupsFoundSoFar: groupsFound,
                    onProgress: onProgress,
                    isCancelled: isCancelled
                )
            case .videoFingerprint:
                summary = try detectByVideoFingerprint(
                    files,
                    levelIndex: levelIndex,
                    levelCount: activeLevels.count,
                    groupsFoundSoFar: groupsFound,
                    onProgress: onProgress,
                    isCancelled: isCancelled
                )
            }

            groupsFound += summary.groupsFound
            reclaimableBytes += summary.reclaimableBytes
        }

        return DuplicateScanSummary(groupsFound: groupsFound, reclaimableBytes: reclaimableBytes)
    }

    private func reportProgress(
        level: DuplicateDetectionLevel,
        levelIndex: Int,
        levelCount: Int,
        processedCount: Int,
        totalCount: Int,
        currentPath: String,
        groupsFoundSoFar: Int,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)?
    ) {
        onProgress?(
            DuplicateScanProgress(
                level: level,
                levelIndex: levelIndex,
                levelCount: levelCount,
                processedCount: processedCount,
                totalCount: totalCount,
                currentPath: currentPath,
                groupsFoundSoFar: groupsFoundSoFar
            )
        )
    }

    private func detectByFilename(
        _ files: [FileRecord],
        levelIndex: Int,
        levelCount: Int,
        groupsFoundSoFar: Int,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> DuplicateScanSummary {
        reportProgress(
            level: .filename,
            levelIndex: levelIndex,
            levelCount: levelCount,
            processedCount: 0,
            totalCount: files.count,
            currentPath: "Grouping files by name…",
            groupsFoundSoFar: groupsFoundSoFar,
            onProgress: onProgress
        )

        if isCancelled?() == true { throw CancellationError() }

        let grouped = Dictionary(grouping: files) { detector.normalizedFilename($0.path) }
        let entries = grouped
            .filter { $0.value.count > 1 }
            .map { (fingerprint: $0.key, members: $0.value) }

        reportProgress(
            level: .filename,
            levelIndex: levelIndex,
            levelCount: levelCount,
            processedCount: files.count,
            totalCount: files.count,
            currentPath: "Saving filename matches…",
            groupsFoundSoFar: groupsFoundSoFar,
            onProgress: onProgress
        )

        return try persistGroups(entries: entries, level: .filename)
    }

    private func detectBySize(
        _ files: [FileRecord],
        levelIndex: Int,
        levelCount: Int,
        groupsFoundSoFar: Int,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> DuplicateScanSummary {
        let sizedFiles = files.filter { $0.size > 0 }

        reportProgress(
            level: .size,
            levelIndex: levelIndex,
            levelCount: levelCount,
            processedCount: 0,
            totalCount: sizedFiles.count,
            currentPath: "Grouping files by size…",
            groupsFoundSoFar: groupsFoundSoFar,
            onProgress: onProgress
        )

        if isCancelled?() == true { throw CancellationError() }

        let grouped = Dictionary(grouping: sizedFiles) { $0.size }
        let entries = grouped
            .filter { $0.value.count > 1 }
            .map { (fingerprint: "size:\($0.key)", members: $0.value) }

        reportProgress(
            level: .size,
            levelIndex: levelIndex,
            levelCount: levelCount,
            processedCount: sizedFiles.count,
            totalCount: sizedFiles.count,
            currentPath: "Saving size matches…",
            groupsFoundSoFar: groupsFoundSoFar,
            onProgress: onProgress
        )

        return try persistGroups(entries: entries, level: .size)
    }

    private func detectByHash(
        _ files: [FileRecord],
        levelIndex: Int,
        levelCount: Int,
        groupsFoundSoFar: Int,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> DuplicateScanSummary {
        var buckets: [String: [FileRecord]] = [:]
        let totalCount = files.count

        for (index, file) in files.enumerated() {
            if isCancelled?() == true { throw CancellationError() }

            reportProgress(
                level: .hash,
                levelIndex: levelIndex,
                levelCount: levelCount,
                processedCount: index,
                totalCount: totalCount,
                currentPath: file.path,
                groupsFoundSoFar: groupsFoundSoFar,
                onProgress: onProgress
            )

            let url = URL(fileURLWithPath: file.path)
            guard FileManager.default.isReadableFile(atPath: url.path) else { continue }
            let hash = try detector.sha256(for: url)
            if let fileID = file.id {
                try database.updateHash(forFileID: fileID, hash: hash)
            }
            buckets[hash, default: []].append(file)
        }

        reportProgress(
            level: .hash,
            levelIndex: levelIndex,
            levelCount: levelCount,
            processedCount: totalCount,
            totalCount: totalCount,
            currentPath: "Saving hash matches…",
            groupsFoundSoFar: groupsFoundSoFar,
            onProgress: onProgress
        )

        let entries = buckets
            .filter { $0.value.count > 1 }
            .map { (fingerprint: $0.key, members: $0.value) }
        return try persistGroups(entries: entries, level: .hash)
    }

    private func detectByVideoFingerprint(
        _ files: [FileRecord],
        levelIndex: Int,
        levelCount: Int,
        groupsFoundSoFar: Int,
        onProgress: (@Sendable (DuplicateScanProgress) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> DuplicateScanSummary {
        let videos = files.filter { $0.category == .video }
        var buckets: [String: [FileRecord]] = [:]

        for (index, file) in videos.enumerated() {
            if isCancelled?() == true { throw CancellationError() }

            reportProgress(
                level: .videoFingerprint,
                levelIndex: levelIndex,
                levelCount: levelCount,
                processedCount: index,
                totalCount: videos.count,
                currentPath: file.path,
                groupsFoundSoFar: groupsFoundSoFar,
                onProgress: onProgress
            )

            let url = URL(fileURLWithPath: file.path)
            guard let fingerprint = detector.videoFingerprint(for: url) else { continue }
            buckets[fingerprint, default: []].append(file)
        }

        reportProgress(
            level: .videoFingerprint,
            levelIndex: levelIndex,
            levelCount: levelCount,
            processedCount: videos.count,
            totalCount: videos.count,
            currentPath: "Saving video matches…",
            groupsFoundSoFar: groupsFoundSoFar,
            onProgress: onProgress
        )

        let entries = buckets
            .filter { $0.value.count > 1 }
            .map { (fingerprint: $0.key, members: $0.value) }
        return try persistGroups(entries: entries, level: .videoFingerprint)
    }

    private func persistGroups(
        entries: [(fingerprint: String, members: [FileRecord])],
        level: DuplicateDetectionLevel
    ) throws -> DuplicateScanSummary {
        var groupsFound = 0
        var reclaimableBytes: Int64 = 0

        for entry in entries {
            let members = entry.members
            let fileIDs = members.compactMap(\.id)
            guard fileIDs.count > 1 else { continue }

            let totalSize = members.reduce(0) { $0 + $1.size }
            let reclaimable = totalSize - (members.first?.size ?? 0)
            _ = try database.createDuplicateGroup(
                DuplicateGroupRecord(
                    detectionLevel: level.rawValue,
                    fingerprint: entry.fingerprint,
                    totalSize: totalSize,
                    fileCount: members.count
                ),
                fileIDs: fileIDs
            )

            groupsFound += 1
            reclaimableBytes += reclaimable
        }

        return DuplicateScanSummary(groupsFound: groupsFound, reclaimableBytes: reclaimableBytes)
    }

    public func loadGroups(forDiskID diskID: Int64, limit: Int = 100) throws -> [DuplicateGroup] {
        let records = try database.duplicateGroups(forDiskID: diskID, limit: limit)
        return try records.compactMap { record in
            guard let groupID = record.id else { return nil }
            let files = try database.members(forGroupID: groupID)
            let reclaimable = record.totalSize - (files.first?.size ?? 0)
            return DuplicateGroup(
                id: groupID,
                level: DuplicateDetectionLevel(rawValue: record.detectionLevel) ?? .hash,
                fingerprint: record.fingerprint,
                totalSize: record.totalSize,
                reclaimableSize: reclaimable,
                files: files
            )
        }
    }

    public func loadGroups(limit: Int = 100) throws -> [DuplicateGroup] {
        let records = try database.duplicateGroups(limit: limit)
        return try records.map { record in
            let files = try database.members(forGroupID: record.id ?? 0)
            let reclaimable = record.totalSize - (files.first?.size ?? 0)
            return DuplicateGroup(
                id: record.id ?? 0,
                level: DuplicateDetectionLevel(rawValue: record.detectionLevel) ?? .hash,
                fingerprint: record.fingerprint,
                totalSize: record.totalSize,
                reclaimableSize: reclaimable,
                files: files
            )
        }
    }
}
