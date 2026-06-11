#!/usr/bin/env swift
import AppKit

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

let outputDirectory = CommandLine.arguments.dropFirst().first
    ?? repoRoot.appendingPathComponent("app/DiskWise/Assets.xcassets/AppIcon.appiconset").path

let sourceImagePath = CommandLine.arguments.dropFirst().dropFirst().first
    ?? repoRoot.appendingPathComponent("website/public/app-icon.png").path

let appIconSourcePath = repoRoot.appendingPathComponent("app/DiskWise/Assets/AppIconSource.png").path

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

let blackThreshold = 28
let feather = 24

func makeTransparentBitmap(from path: String) -> (rep: NSBitmapImageRep, width: Int, height: Int)? {
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }

    let width = cgImage.width
    let height = cgImage.height

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
        return nil
    }

    rep.size = NSSize(width: width, height: height)
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let data = rep.bitmapData else { return nil }
    let bytesPerRow = rep.bytesPerRow

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            let red = Int(data[offset])
            let green = Int(data[offset + 1])
            let blue = Int(data[offset + 2])
            let luminance = (red * 299 + green * 587 + blue * 114) / 1000

            if luminance <= blackThreshold {
                data[offset] = 0
                data[offset + 1] = 0
                data[offset + 2] = 0
                data[offset + 3] = 0
            } else if luminance < blackThreshold + feather {
                let alpha = (luminance - blackThreshold) * 255 / feather
                data[offset + 3] = UInt8(min(255, max(0, alpha)))
            } else {
                data[offset + 3] = 255
            }
        }
    }

    return (rep, width, height)
}

func cropToOpaqueBounds(_ rep: NSBitmapImageRep, width: Int, height: Int, padding: Int = 6) -> NSBitmapImageRep {
    guard let data = rep.bitmapData else { return rep }
    let bytesPerRow = rep.bytesPerRow

    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0

    for y in 0..<height {
        for x in 0..<width {
            let alpha = data[y * bytesPerRow + x * 4 + 3]
            if alpha > 12 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    if maxX <= minX || maxY <= minY {
        return rep
    }

    minX = max(0, minX - padding)
    minY = max(0, minY - padding)
    maxX = min(width - 1, maxX + padding)
    maxY = min(height - 1, maxY + padding)

    let cropWidth = maxX - minX + 1
    let cropHeight = maxY - minY + 1

    guard let cropped = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: cropWidth,
        pixelsHigh: cropHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let cropData = cropped.bitmapData else {
        return rep
    }

    cropped.size = NSSize(width: cropWidth, height: cropHeight)

    let cropBytesPerRow = cropped.bytesPerRow
    for y in 0..<cropHeight {
        for x in 0..<cropWidth {
            let src = (minY + y) * bytesPerRow + (minX + x) * 4
            let dst = y * cropBytesPerRow + x * 4
            cropData[dst] = data[src]
            cropData[dst + 1] = data[src + 1]
            cropData[dst + 2] = data[src + 2]
            cropData[dst + 3] = data[src + 3]
        }
    }

    return cropped
}

func image(from rep: NSBitmapImageRep) -> NSImage {
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}

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

    return image(from: rep)
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

guard let initial = makeTransparentBitmap(from: sourceImagePath) else {
    fputs("error: unable to load source icon at \(sourceImagePath)\n", stderr)
    exit(1)
}

let cropped = cropToOpaqueBounds(initial.rep, width: initial.width, height: initial.height)
var normalizedSource = squareCanvas(from: image(from: cropped))
normalizedSource.size = NSSize(
    width: normalizedSource.representations.first?.pixelsWide ?? Int(normalizedSource.size.width),
    height: normalizedSource.representations.first?.pixelsHigh ?? Int(normalizedSource.size.height)
)

print("Using source icon: \(sourceImagePath)")

let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

for entry in sizes {
    let rep = resizedIcon(from: normalizedSource, pixels: entry.size)
    try savePNG(rep, to: directoryURL.appendingPathComponent(entry.name))
    print("Generated \(entry.name) (\(entry.size)x\(entry.size))")
}

let master1024 = directoryURL.appendingPathComponent("icon_512x512@2x.png")
let appIconSourceURL = URL(fileURLWithPath: appIconSourcePath)
try? FileManager.default.removeItem(at: appIconSourceURL)
try FileManager.default.copyItem(at: master1024, to: appIconSourceURL)
print("Synced AppIconSource.png from 1024px master")

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
