import XCTest
import DatabaseKit
@testable import AIKit

final class ScreenshotInsightEngineTests: XCTestCase {
    func testOTPScreenshotIsRecommendedForDeletion() {
        let file = FileRecord(
            diskID: 1,
            path: "/Users/me/Desktop/Screenshot 2024-01-01 at 12.00.00.png",
            size: 120_000,
            category: .photo,
            subcategory: "screenshot",
            modifiedAt: Calendar.current.date(byAdding: .year, value: -2, to: Date()),
            extensionName: "png"
        )

        let insight = ScreenshotInsightEngine.insight(for: file, ocrText: "Your verification code is 482913")
        XCTAssertEqual(insight.action, .trash)
        XCTAssertLessThan(insight.keepScore, 40)
        XCTAssertTrue(insight.reason.lowercased().contains("code") || insight.reason.lowercased().contains("password"))
    }

    func testReceiptScreenshotIsLikelyKeep() {
        let file = FileRecord(
            diskID: 1,
            path: "/Users/me/Desktop/Screenshot 2026-09-10 at 9.00.00.png",
            size: 400_000,
            category: .photo,
            subcategory: "screenshot",
            lastAccessed: Date(),
            extensionName: "png"
        )

        let insight = ScreenshotInsightEngine.insight(for: file, ocrText: "Invoice #4412\nTotal $86.00")
        XCTAssertNotEqual(insight.action, .trash)
        XCTAssertGreaterThanOrEqual(insight.keepScore, 40)
        XCTAssertTrue(insight.label.lowercased().contains("invoice") || insight.reason.lowercased().contains("document"))
    }

    func testWhatsAppLabel() {
        let file = FileRecord(
            diskID: 1,
            path: "/Users/me/Desktop/Screenshot.png",
            size: 200_000,
            category: .photo,
            extensionName: "png"
        )
        let insight = ScreenshotInsightEngine.insight(for: file, ocrText: "WhatsApp\nYesterday")
        XCTAssertEqual(insight.label, "WhatsApp chat")
        XCTAssertEqual(insight.sourceApp, "WhatsApp chat")
    }

    func testScreenshotCleanupIsReviewFirst() {
        XCTAssertEqual(ActionBucket.bucket(forRecommendationType: "delete_screenshots"), .reviewFirst)
    }
}
