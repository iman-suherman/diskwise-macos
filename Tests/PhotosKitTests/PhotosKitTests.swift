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

final class PhotosScreenshotInsightEngineTests: XCTestCase {
    func testOTPScreenshotIsRecommendedForDeletion() {
        let asset = PhotoAssetRecord(
            id: "otp",
            mediaType: .image,
            byteSize: 120_000,
            pixelWidth: 1170,
            pixelHeight: 2532,
            creationDate: Calendar.current.date(byAdding: .year, value: -2, to: Date()),
            isScreenshot: true,
            originalFilename: "Screenshot 2024-01-01.png"
        )
        let insight = PhotosScreenshotInsightEngine.insight(
            for: asset,
            ocrText: "Your verification code is 482913"
        )
        XCTAssertEqual(insight.action, .trash)
        XCTAssertLessThan(insight.keepScore, 40)
        XCTAssertTrue(insight.reason.lowercased().contains("code") || insight.reason.lowercased().contains("password"))
    }

    func testReceiptScreenshotIsLikelyKeep() {
        let asset = PhotoAssetRecord(
            id: "receipt",
            mediaType: .image,
            byteSize: 400_000,
            pixelWidth: 1170,
            pixelHeight: 2532,
            creationDate: Date(),
            isScreenshot: true
        )
        let insight = PhotosScreenshotInsightEngine.insight(
            for: asset,
            ocrText: "Invoice #4412\nTotal $86.00"
        )
        XCTAssertNotEqual(insight.action, .trash)
        XCTAssertGreaterThanOrEqual(insight.keepScore, 40)
        XCTAssertTrue(
            insight.label.lowercased().contains("invoice") || insight.reason.lowercased().contains("document")
        )
    }

    func testWhatsAppLabelFromOCR() {
        let asset = PhotoAssetRecord(
            id: "wa",
            mediaType: .image,
            byteSize: 200_000,
            pixelWidth: 1170,
            pixelHeight: 2532,
            isScreenshot: true
        )
        let insight = PhotosScreenshotInsightEngine.insight(for: asset, ocrText: "WhatsApp\nYesterday")
        XCTAssertEqual(insight.label, "WhatsApp chat")
        XCTAssertEqual(insight.sourceApp, "WhatsApp chat")
    }

    func testDateLabelWithoutOCR() {
        let created = Date(timeIntervalSince1970: 1_725_552_000)
        let asset = PhotoAssetRecord(
            id: "plain",
            mediaType: .image,
            byteSize: 200_000,
            pixelWidth: 1170,
            pixelHeight: 2532,
            creationDate: created,
            isScreenshot: true,
            originalFilename: "IMG_2048.PNG"
        )
        let insight = PhotosScreenshotInsightEngine.insight(for: asset)
        XCTAssertTrue(insight.label.hasPrefix("Screenshot ·"))
        XCTAssertFalse(insight.label == "Screenshot")
    }

    func testRankPutsTrashCandidatesFirst() {
        let old = PhotoAssetRecord(
            id: "old",
            mediaType: .image,
            byteSize: 90_000,
            pixelWidth: 100,
            pixelHeight: 200,
            creationDate: Calendar.current.date(byAdding: .year, value: -2, to: Date()),
            isScreenshot: true
        )
        let favorite = PhotoAssetRecord(
            id: "fav",
            mediaType: .image,
            byteSize: 400_000,
            pixelWidth: 100,
            pixelHeight: 200,
            creationDate: Date(),
            isScreenshot: true,
            isFavorite: true
        )
        let ranked = PhotosScreenshotInsightEngine.ranked([favorite, old])
        XCTAssertEqual(ranked.first?.id, "old")
        XCTAssertEqual(ranked.last?.id, "fav")
    }
}
