// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskWise",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "DatabaseKit", targets: ["DatabaseKit"]),
        .library(name: "DiskScannerKit", targets: ["DiskScannerKit"]),
        .library(name: "MetadataKit", targets: ["MetadataKit"]),
        .library(name: "DuplicateKit", targets: ["DuplicateKit"]),
        .library(name: "CleanupKit", targets: ["CleanupKit"]),
        .library(name: "AIKit", targets: ["AIKit"]),
        .library(name: "MaintenanceKit", targets: ["MaintenanceKit"]),
        .library(name: "PhotosKit", targets: ["PhotosKit"]),
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
            dependencies: ["DatabaseKit", "MaintenanceKit"],
            linkerSettings: [
                .linkedFramework("FoundationModels", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "AIKitTests",
            dependencies: ["AIKit", "MaintenanceKit"]
        ),
        .target(
            name: "MaintenanceKit",
            dependencies: ["DatabaseKit", "CleanupKit"]
        ),
        .testTarget(
            name: "MaintenanceKitTests",
            dependencies: ["MaintenanceKit"]
        ),
        .target(
            name: "PhotosKit",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("Photos", .when(platforms: [.iOS, .macOS])),
            ]
        ),
        .testTarget(
            name: "PhotosKitTests",
            dependencies: ["PhotosKit"]
        ),
    ]
)
