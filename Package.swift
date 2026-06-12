// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskWise",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "DatabaseKit", targets: ["DatabaseKit"]),
        .library(name: "DiskScannerKit", targets: ["DiskScannerKit"]),
        .library(name: "MetadataKit", targets: ["MetadataKit"]),
        .library(name: "DuplicateKit", targets: ["DuplicateKit"]),
        .library(name: "CleanupKit", targets: ["CleanupKit"]),
        .library(name: "AIKit", targets: ["AIKit"]),
        .library(name: "MaintenanceKit", targets: ["MaintenanceKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "DatabaseKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "DatabaseKitTests",
            dependencies: ["DatabaseKit"]
        ),
        .target(
            name: "DiskScannerKit",
            dependencies: ["DatabaseKit"]
        ),
        .testTarget(
            name: "DiskScannerKitTests",
            dependencies: ["DiskScannerKit"]
        ),
        .target(
            name: "MetadataKit",
            dependencies: ["DatabaseKit"]
        ),
        .target(
            name: "DuplicateKit",
            dependencies: ["DatabaseKit", "MetadataKit"]
        ),
        .testTarget(
            name: "DuplicateKitTests",
            dependencies: ["DuplicateKit"]
        ),
        .target(
            name: "CleanupKit",
            dependencies: ["DatabaseKit"]
        ),
        .target(
            name: "AIKit",
            dependencies: ["DatabaseKit"]
        ),
        .target(
            name: "MaintenanceKit",
            dependencies: ["DatabaseKit", "CleanupKit"]
        ),
        .testTarget(
            name: "MaintenanceKitTests",
            dependencies: ["MaintenanceKit"]
        ),
    ]
)
