#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

let sourcePath = CommandLine.arguments.dropFirst().first
    ?? repoRoot.appendingPathComponent("app/DiskWise/Assets/AppIconSource.png").path
let outputPath = CommandLine.arguments.dropFirst().dropFirst().first
    ?? repoRoot.appendingPathComponent("website/public/app-icon.png").path

let blackThreshold: UInt8 = 28

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
            let red = data[offset]
            let green = data[offset + 1]
            let blue = data[offset + 2]

            if red <= blackThreshold && green <= blackThreshold && blue <= blackThreshold {
                data[offset + 3] = 0
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

guard let initial = makeTransparentBitmap(from: sourcePath) else {
    fputs("prepare-website-assets: failed to load \(sourcePath)\n", stderr)
    exit(1)
}

let cropped = cropToOpaqueBounds(initial.rep, width: initial.width, height: initial.height)

guard let png = cropped.representation(using: .png, properties: [:]) else {
    fputs("prepare-website-assets: failed to encode PNG\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)

let heroURL = outputURL.deletingLastPathComponent().appendingPathComponent("hero.png")
try png.write(to: heroURL)

fputs("prepare-website-assets: wrote \(outputPath)\n", stderr)
