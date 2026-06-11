#!/usr/bin/env swift
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let screenshotsDir = repoRoot.appendingPathComponent("website/public", isDirectory: true)

let matteThreshold = 42
let peelThreshold = 82
let peelPasses = 48
let featherRange = 16

func luminance(_ r: Int, _ g: Int, _ b: Int) -> Int {
    (r * 299 + g * 587 + b * 114) / 1000
}

func loadBitmap(from path: String) -> NSBitmapImageRep? {
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
    return rep
}

func removeOuterMatte(_ rep: NSBitmapImageRep) {
    guard let data = rep.bitmapData else { return }

    let width = rep.pixelsWide
    let height = rep.pixelsHigh
    let bytesPerRow = rep.bytesPerRow
    let pixelCount = width * height
    var queue: [Int] = []
    var visited = [Bool](repeating: false, count: pixelCount)

    func index(_ x: Int, _ y: Int) -> Int { y * width + x }

    func enqueueIfMatte(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let idx = index(x, y)
        guard !visited[idx] else { return }

        let offset = y * bytesPerRow + x * 4
        let alpha = Int(data[offset + 3])
        let red = Int(data[offset])
        let green = Int(data[offset + 1])
        let blue = Int(data[offset + 2])
        let lum = luminance(red, green, blue)

        let isTransparent = alpha <= 8
        let isDarkMatte = alpha > 8 && lum <= matteThreshold

        guard isTransparent || isDarkMatte else { return }

        visited[idx] = true
        queue.append(idx)
    }

    for x in 0..<width {
        enqueueIfMatte(x, 0)
        enqueueIfMatte(x, height - 1)
    }
    for y in 0..<height {
        enqueueIfMatte(0, y)
        enqueueIfMatte(width - 1, y)
    }

    var head = 0
    while head < queue.count {
        let idx = queue[head]
        head += 1

        let x = idx % width
        let y = idx / width
        let offset = y * bytesPerRow + x * 4

        data[offset] = 0
        data[offset + 1] = 0
        data[offset + 2] = 0
        data[offset + 3] = 0

        enqueueIfMatte(x - 1, y)
        enqueueIfMatte(x + 1, y)
        enqueueIfMatte(x, y - 1)
        enqueueIfMatte(x, y + 1)
    }

    for _ in 0..<peelPasses {
        var peeled: [Int] = []

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let alpha = Int(data[offset + 3])
                guard alpha > 12 else { continue }

                let red = Int(data[offset])
                let green = Int(data[offset + 1])
                let blue = Int(data[offset + 2])
                let lum = luminance(red, green, blue)
                guard lum <= peelThreshold else { continue }

                let touchesTransparency = [
                    (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1),
                    (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1),
                ].contains { nx, ny in
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { return true }
                    return data[ny * bytesPerRow + nx * 4 + 3] <= 12
                }

                guard touchesTransparency else { continue }
                peeled.append(offset)
            }
        }

        if peeled.isEmpty {
            break
        }

        for offset in peeled {
            data[offset] = 0
            data[offset + 1] = 0
            data[offset + 2] = 0
            data[offset + 3] = 0
        }
    }

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            let alpha = Int(data[offset + 3])
            guard alpha > 0 else { continue }

            let red = Int(data[offset])
            let green = Int(data[offset + 1])
            let blue = Int(data[offset + 2])
            let lum = luminance(red, green, blue)
            guard lum <= peelThreshold + featherRange else { continue }

            let touchesTransparency = [
                (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1),
            ].contains { nx, ny in
                guard nx >= 0, ny >= 0, nx < width, ny < height else { return true }
                return data[ny * bytesPerRow + nx * 4 + 3] <= 12
            }

            guard touchesTransparency else { continue }

            if lum <= peelThreshold {
                data[offset] = 0
                data[offset + 1] = 0
                data[offset + 2] = 0
                data[offset + 3] = 0
            } else {
                let alphaValue = (lum - peelThreshold) * 255 / featherRange
                data[offset + 3] = UInt8(min(255, max(0, alphaValue)))
            }
        }
    }
}

func cropToOpaqueBounds(_ rep: NSBitmapImageRep, padding: Int = 0) -> NSBitmapImageRep {
    guard let data = rep.bitmapData else { return rep }

    let width = rep.pixelsWide
    let height = rep.pixelsHigh
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

    cropped.size = NSSize(
        width: rep.size.width * CGFloat(cropWidth) / CGFloat(width),
        height: rep.size.height * CGFloat(cropHeight) / CGFloat(height)
    )

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

let inputPaths: [String]
if CommandLine.arguments.count > 1 {
    inputPaths = Array(CommandLine.arguments.dropFirst())
} else {
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: screenshotsDir.path)) ?? []
    inputPaths = contents
        .filter { $0.hasPrefix("app-screenshot-") && $0.hasSuffix(".png") }
        .sorted()
        .map { screenshotsDir.appendingPathComponent($0).path }
}

guard !inputPaths.isEmpty else {
    fputs("prepare-website-screenshots: no screenshots found\n", stderr)
    exit(1)
}

for path in inputPaths {
    guard let rep = loadBitmap(from: path) else {
        fputs("prepare-website-screenshots: failed to load \(path)\n", stderr)
        exit(1)
    }

    removeOuterMatte(rep)
    let cropped = cropToOpaqueBounds(rep, padding: 0)

    guard let png = cropped.representation(using: .png, properties: [:]) else {
        fputs("prepare-website-screenshots: failed to encode \(path)\n", stderr)
        exit(1)
    }

    try png.write(to: URL(fileURLWithPath: path))
    fputs(
        "prepare-website-screenshots: wrote \(path) (\(cropped.pixelsWide)x\(cropped.pixelsHigh))\n",
        stderr
    )
}
