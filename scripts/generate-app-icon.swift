#!/usr/bin/env swift
import AppKit

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

let outputDirectory = CommandLine.arguments.dropFirst().first
    ?? repoRoot.appendingPathComponent("app/DiskWise/Assets.xcassets/AppIcon.appiconset").path

let sourceImagePath = CommandLine.arguments.dropFirst().dropFirst().first
    ?? repoRoot.appendingPathComponent("app/DiskWise/Assets/AppIconSource.png").path

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func squareCanvas(from source: NSImage) -> NSImage {
    let sourceSize = source.size
    let side = max(sourceSize.width, sourceSize.height)
    guard side > sourceSize.width || side > sourceSize.height else {
        return source
    }

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(side),
        pixelsHigh: Int(side),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return source
    }

    rep.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let origin = NSPoint(
        x: (side - sourceSize.width) / 2,
        y: (side - sourceSize.height) / 2
    )
    source.draw(
        in: NSRect(origin: origin, size: sourceSize),
        from: NSRect(origin: .zero, size: sourceSize),
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: nil
    )

    let image = NSImage(size: NSSize(width: side, height: side))
    image.addRepresentation(rep)
    return image
}

func resizedIcon(from source: NSImage, pixels: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap for \(pixels)px icon")
    }

    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGraphicsContext.current?.imageInterpolation = .high

    // Ensure unused canvas pixels stay transparent (not black) in Finder/Dock.
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()

    let sourceSize = source.size
    let scale = max(
        CGFloat(pixels) / sourceSize.width,
        CGFloat(pixels) / sourceSize.height
    )
    let drawnSize = NSSize(
        width: sourceSize.width * scale,
        height: sourceSize.height * scale
    )
    let origin = NSPoint(
        x: (CGFloat(pixels) - drawnSize.width) / 2,
        y: (CGFloat(pixels) - drawnSize.height) / 2
    )

    source.draw(
        in: NSRect(origin: origin, size: drawnSize),
        from: NSRect(origin: .zero, size: sourceSize),
        operation: .copy,
        fraction: 1,
        respectFlipped: false,
        hints: nil
    )

    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGenerator", code: 1)
    }
    try data.write(to: url)
}

guard let sourceImage = NSImage(contentsOf: URL(fileURLWithPath: sourceImagePath)) else {
    fputs("error: unable to load source icon at \(sourceImagePath)\n", stderr)
    exit(1)
}

sourceImage.size = NSSize(
    width: sourceImage.representations.first?.pixelsWide ?? Int(sourceImage.size.width),
    height: sourceImage.representations.first?.pixelsHigh ?? Int(sourceImage.size.height)
)

let normalizedSource = squareCanvas(from: sourceImage)
normalizedSource.size = NSSize(
    width: normalizedSource.representations.first?.pixelsWide ?? Int(normalizedSource.size.width),
    height: normalizedSource.representations.first?.pixelsHigh ?? Int(normalizedSource.size.height)
)

let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

for entry in sizes {
    let rep = resizedIcon(from: normalizedSource, pixels: entry.size)
    try savePNG(rep, to: directoryURL.appendingPathComponent(entry.name))
    print("Generated \(entry.name) (\(entry.size)x\(entry.size))")
}

let icnsOutput = directoryURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Assets/AppIcon.icns")

let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("DiskWiseAppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for entry in sizes {
    let source = directoryURL.appendingPathComponent(entry.name)
    let destination = iconsetURL.appendingPathComponent(entry.name)
    try FileManager.default.copyItem(at: source, to: destination)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsOutput.path]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconsetURL)

if process.terminationStatus == 0 {
    print("Generated \(icnsOutput.path)")
} else {
    fputs("error: iconutil failed to build AppIcon.icns\n", stderr)
    exit(1)
}
