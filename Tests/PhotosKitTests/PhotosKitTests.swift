import Foundation
import PhotosKit
import XCTest

final class PhotosDuplicateEngineTests: XCTestCase {
    private let engine = PhotosDuplicateEngine()

    func testExactDuplicatesGroupByFingerprint() {
        let a = PhotoAssetRecord(
            id: "a",
            mediaType: .image,
            byteSize: 1_000,
            pixelWidth: 100,
            pixelHeight: 200,
            creationDate: Date()
        )
        let b = PhotoAssetRecord(
            id: "b",
            mediaType: .image,
            byteSize: 1_000,
            pixelWidth: 100,
            pixelHeight: 200,
            creationDate: Date()
        )
        let c = PhotoAssetRecord(
            id: "c",
            mediaType: .image,
            byteSize: 2_000,
            pixelWidth: 100,
            pixelHeight: 200,
            creationDate: Date()
        )

        let groups = engine.findExactDuplicates(in: [a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].assets.map(\.id)), Set(["a", "b"]))
        XCTAssertEqual(groups[0].reclaimableSize, 1_000)
    }

    func testSimilarRequiresSameDayAndCloseDimensions() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let a = PhotoAssetRecord(
            id: "a",
            mediaType: .image,
            byteSize: 1_000,
            pixelWidth: 1000,
            pixelHeight: 1000,
            creationDate: day
        )
        let b = PhotoAssetRecord(
            id: "b",
            mediaType: .image,
            byteSize: 1_050,
            pixelWidth: 1010,
            pixelHeight: 1000,
            creationDate: day
        )
        let otherDay = PhotoAssetRecord(
            id: "c",
            mediaType: .image,
            byteSize: 1_050,
            pixelWidth: 1010,
            pixelHeight: 1000,
            creationDate: day.addingTimeInterval(86_400 * 3)
        )

        let groups = engine.findSimilar(in: [a, b, otherDay])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].assets.map(\.id)), Set(["a", "b"]))
    }

    func testSuggestedKeepPrefersFavorite() {
        let keep = PhotoAssetRecord(
            id: "keep",
            mediaType: .image,
            byteSize: 100,
            pixelWidth: 10,
            pixelHeight: 10,
            isFavorite: true
        )
        let drop = PhotoAssetRecord(
            id: "drop",
            mediaType: .image,
            byteSize: 9_000,
            pixelWidth: 10,
            pixelHeight: 10
        )
        let group = PhotosDuplicateGroup(id: "g", fingerprint: "f", assets: [drop, keep])
        XCTAssertEqual(group.suggestedKeepID, "keep")
        XCTAssertEqual(group.suggestedCleanupIDs, ["drop"])
    }
}

final class PhotosInsightEngineTests: XCTestCase {
    func testReportSurfacesScreenshotsAndDuplicates() {
        let day = Date()
        let assets = [
            PhotoAssetRecord(
                id: "d1",
                mediaType: .image,
                byteSize: 500,
                pixelWidth: 50,
                pixelHeight: 50,
                creationDate: day
            ),
            PhotoAssetRecord(
                id: "d2",
                mediaType: .image,
                byteSize: 500,
                pixelWidth: 50,
                pixelHeight: 50,
                creationDate: day
            ),
            PhotoAssetRecord(
                id: "s1",
                mediaType: .image,
                byteSize: 200,
                pixelWidth: 100,
                pixelHeight: 200,
                creationDate: day,
                isScreenshot: true
            ),
            PhotoAssetRecord(
                id: "v1",
                mediaType: .video,
                byteSize: 150 * 1024 * 1024,
                pixelWidth: 1920,
                pixelHeight: 1080,
                durationSeconds: 60,
                creationDate: day
            ),
        ]

        let report = PhotosInsightEngine().analyze(assets)
        XCTAssertEqual(report.totalAssets, 4)
        XCTAssertTrue(report.buckets.contains { $0.bucket == .exactDuplicates })
        XCTAssertTrue(report.buckets.contains { $0.bucket == .screenshots })
        XCTAssertTrue(report.buckets.contains { $0.bucket == .largeVideos })
        XCTAssertFalse(report.recommendations.isEmpty)
        XCTAssertGreaterThan(report.reclaimableBytes, 0)
    }

    func testAssetsAreNotDoubleCountedAcrossBuckets() {
        let assets = [
            PhotoAssetRecord(
                id: "shot",
                mediaType: .image,
                byteSize: 100,
                pixelWidth: 10,
                pixelHeight: 10,
                isScreenshot: true
            ),
            PhotoAssetRecord(
                id: "shot2",
                mediaType: .image,
                byteSize: 100,
                pixelWidth: 10,
                pixelHeight: 10,
                isScreenshot: true
            ),
        ]
        // Exact dupes claim cleanup IDs first; screenshot bucket should not re-list them.
        let report = PhotosInsightEngine().analyze(assets)
        let dupeIDs = Set(report.buckets.first { $0.bucket == .exactDuplicates }?.assetIDs ?? [])
        let shotIDs = Set(report.buckets.first { $0.bucket == .screenshots }?.assetIDs ?? [])
        XCTAssertTrue(dupeIDs.isDisjoint(with: shotIDs))
    }
}
