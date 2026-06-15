#!/usr/bin/env swift
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

let sourcePath = CommandLine.arguments.dropFirst().first
    ?? repoRoot.appendingPathComponent("app/DiskWise/Assets/DockScanning.raw.png").path
let imagesetDir = repoRoot.appendingPathComponent(
    "app/DiskWise/Assets.xcassets/DockScanning.imageset"
).path
let baseImagesetDir = repoRoot.appendingPathComponent(
    "app/DiskWise/Assets.xcassets/DockScanningBase.imageset"
).path
let ringImagesetDir = repoRoot.appendingPathComponent(
    "app/DiskWise/Assets.xcassets/DockScanningRing.imageset"
).path
let rawArchivePath = repoRoot.appendingPathComponent("app/DiskWise/Assets/DockScanning.raw.png").path

let blackThreshold = 28
let whiteThreshold = 238
let lightFloodThreshold = 228
let feather = 24
let ringInner = 0.355
let ringOuter = 0.495
let outputSize = 1024
let iconCornerRadiusFraction = 0.2237

func clipToIconShape(side: CGFloat) {
    let radius = side * iconCornerRadiusFraction
    let path = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: side, height: side),
        xRadius: radius,
        yRadius: radius
    )
    path.addClip()
}

enum BackgroundMode {
    case dark
    case light
}

func luminance(red: Int, green: Int, blue: Int) -> Int {
    (red * 299 + green * 587 + blue * 114) / 1000
}

func loadBitmap(from path: String) -> (rep: NSBitmapImageRep, width: Int, height: Int)? {
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
    return (rep, width, height)
}

func detectBackgroundMode(rep: NSBitmapImageRep, width: Int, height: Int) -> BackgroundMode {
    guard let data = rep.bitmapData else { return .dark }
    let bytesPerRow = rep.bytesPerRow
    let samplePoints = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
    var totalLuminance = 0
    for (x, y) in samplePoints {
        let offset = y * bytesPerRow + x * 4
        totalLuminance += luminance(
            red: Int(data[offset]),
            green: Int(data[offset + 1]),
            blue: Int(data[offset + 2])
        )
    }
    return totalLuminance / samplePoints.count >= 128 ? .light : .dark
}

func isBackgroundPixel(red: Int, green: Int, blue: Int, mode: BackgroundMode, forFloodFill: Bool = false) -> Bool {
    switch mode {
    case .dark:
        return luminance(red: red, green: green, blue: blue) <= blackThreshold
    case .light:
        let threshold = forFloodFill ? lightFloodThreshold : whiteThreshold
        return min(red, green, blue) >= threshold
    }
}

func removeBackground(rep: NSBitmapImageRep, width: Int, height: Int, mode: BackgroundMode) {
    guard let data = rep.bitmapData else { return }
    let bytesPerRow = rep.bytesPerRow
    let pixelCount = width * height
    var visited = [Bool](repeating: false, count: pixelCount)
    var queue: [(Int, Int)] = []

    for x in 0..<width {
        queue.append((x, 0))
        queue.append((x, height - 1))
    }
    for y in 0..<height {
        queue.append((0, y))
        queue.append((width - 1, y))
    }

    while !queue.isEmpty {
        let (x, y) = queue.removeFirst()
        let index = y * width + x
        if visited[index] { continue }
        visited[index] = true

        let offset = y * bytesPerRow + x * 4
        let red = Int(data[offset])
        let green = Int(data[offset + 1])
        let blue = Int(data[offset + 2])
        guard isBackgroundPixel(red: red, green: green, blue: blue, mode: mode, forFloodFill: true) else { continue }

        data[offset + 3] = 0
        if x > 0 { queue.append((x - 1, y)) }
        if x + 1 < width { queue.append((x + 1, y)) }
        if y > 0 { queue.append((x, y - 1)) }
        if y + 1 < height { queue.append((x, y + 1)) }
    }

    if mode == .dark {
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let red = Int(data[offset])
                let green = Int(data[offset + 1])
                let blue = Int(data[offset + 2])
                let value = luminance(red: red, green: green, blue: blue)
                if value <= blackThreshold {
                    data[offset + 3] = 0
                } else if value < blackThreshold + feather {
                    let alpha = (value - blackThreshold) * 255 / feather
                    data[offset + 3] = UInt8(min(255, max(0, alpha)))
                } else {
                    data[offset + 3] = 255
                }
            }
        }
    } else {
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                if data[offset + 3] == 0 { continue }
                let minimum = min(Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
                if minimum >= whiteThreshold {
                    data[offset + 3] = 255
                } else if minimum >= whiteThreshold - feather {
                    let alpha = (whiteThreshold - minimum) * 255 / feather
                    data[offset + 3] = UInt8(min(255, max(0, alpha)))
                } else {
                    data[offset + 3] = 255
                }
            }
        }
    }
}

func removeDarkMatte(rep: NSBitmapImageRep, width: Int, height: Int) {
    guard let data = rep.bitmapData else { return }
    let bytesPerRow = rep.bytesPerRow

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            if data[offset + 3] == 0 { continue }

            let red = Int(data[offset])
            let green = Int(data[offset + 1])
            let blue = Int(data[offset + 2])
            let value = luminance(red: red, green: green, blue: blue)

            if value <= blackThreshold {
                data[offset] = 0
                data[offset + 1] = 0
                data[offset + 2] = 0
                data[offset + 3] = 0
            } else if value < blackThreshold + feather {
                let alpha = (value - blackThreshold) * 255 / feather
                data[offset + 3] = UInt8(min(255, max(0, alpha)))
            }
        }
    }
}

func finalizeTransparentBitmap(rep: NSBitmapImageRep, width: Int, height: Int, mode: BackgroundMode) {
    if mode == .light {
        removeDarkMatte(rep: rep, width: width, height: height)
    }
}

func splitLayers(from rep: NSBitmapImageRep, width: Int, height: Int) -> (NSBitmapImageRep, NSBitmapImageRep) {
    guard let base = NSBitmapImageRep(
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
    ), let ring = NSBitmapImageRep(
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
    ), let sourceData = rep.bitmapData,
    let baseData = base.bitmapData,
    let ringData = ring.bitmapData else {
        fatalError("Unable to allocate layer bitmaps")
    }

    base.size = rep.size
    ring.size = rep.size
    let bytesPerRow = rep.bytesPerRow
    let centerX = Double(width) / 2
    let centerY = Double(height) / 2
    let half = Double(min(width, height)) / 2

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            let dx = Double(x) - centerX
            let dy = Double(y) - centerY
            let normalizedRadius = hypot(dx, dy) / half
            let alpha = sourceData[offset + 3]

            baseData[offset] = 0
            baseData[offset + 1] = 0
            baseData[offset + 2] = 0
            baseData[offset + 3] = 0
            ringData[offset] = 0
            ringData[offset + 1] = 0
            ringData[offset + 2] = 0
            ringData[offset + 3] = 0

            guard alpha > 12 else { continue }

            if normalizedRadius < ringInner {
                baseData[offset] = sourceData[offset]
                baseData[offset + 1] = sourceData[offset + 1]
                baseData[offset + 2] = sourceData[offset + 2]
                baseData[offset + 3] = sourceData[offset + 3]
            } else if normalizedRadius <= ringOuter {
                ringData[offset] = sourceData[offset]
                ringData[offset + 1] = sourceData[offset + 1]
                ringData[offset + 2] = sourceData[offset + 2]
                ringData[offset + 3] = sourceData[offset + 3]
            }
        }
    }

    return (base, ring)
}

func resized(_ rep: NSBitmapImageRep, pixels: Int) -> NSBitmapImageRep {
    guard let output = NSBitmapImageRep(
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
        fatalError("Unable to resize bitmap")
    }

    output.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    clipToIconShape(side: CGFloat(pixels))

    let source = NSImage(size: rep.size)
    source.addRepresentation(rep)
    let sourceSize = source.size
    let scale = max(CGFloat(pixels) / sourceSize.width, CGFloat(pixels) / sourceSize.height)
    let drawnSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
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
    return output
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DockScanning", code: 1)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

func writeImageset(_ directory: String, filename: String) throws {
    let dirURL = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    let contents: [String: Any] = [
        "images": [
            ["filename": filename, "idiom": "universal", "scale": "1x"],
            ["idiom": "universal", "scale": "2x"],
            ["idiom": "universal", "scale": "3x"],
        ],
        "info": ["author": "xcode", "version": 1],
    ]
    let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted])
    try data.write(to: dirURL.appendingPathComponent("Contents.json"))
}

guard let initial = loadBitmap(from: sourcePath) else {
    fputs("prepare-dock-scanning-icon: failed to load \(sourcePath)\n", stderr)
    exit(1)
}

let mode = detectBackgroundMode(rep: initial.rep, width: initial.width, height: initial.height)
removeBackground(rep: initial.rep, width: initial.width, height: initial.height, mode: mode)
finalizeTransparentBitmap(rep: initial.rep, width: initial.width, height: initial.height, mode: mode)

let (baseRep, ringRep) = splitLayers(from: initial.rep, width: initial.width, height: initial.height)
let fullRep = resized(initial.rep, pixels: outputSize)
let baseOutput = resized(baseRep, pixels: outputSize)
let ringOutput = resized(ringRep, pixels: outputSize)

try writeImageset(imagesetDir, filename: "scanning.png")
try writePNG(fullRep, to: "\(imagesetDir)/scanning.png")

try writeImageset(baseImagesetDir, filename: "base.png")
try writePNG(baseOutput, to: "\(baseImagesetDir)/base.png")

try writeImageset(ringImagesetDir, filename: "ring.png")
try writePNG(ringOutput, to: "\(ringImagesetDir)/ring.png")

if sourcePath != rawArchivePath, CommandLine.arguments.dropFirst().first != nil {
    let sourceURL = URL(fileURLWithPath: sourcePath)
    let rawURL = URL(fileURLWithPath: rawArchivePath)
    try? FileManager.default.removeItem(at: rawURL)
    try FileManager.default.copyItem(at: sourceURL, to: rawURL)
    fputs("prepare-dock-scanning-icon: synced DockScanning.raw.png\n", stderr)
}

fputs("prepare-dock-scanning-icon: wrote dock scanning assets from \(sourcePath)\n", stderr)
