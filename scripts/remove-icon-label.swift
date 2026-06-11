#!/usr/bin/env swift
import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let outputPath = repoRoot.appendingPathComponent("app/DiskWise/Assets/AppIconSource.png").path
let rawPath = repoRoot.appendingPathComponent("app/DiskWise/Assets/AppIconSource.raw.png").path
let inputPath = CommandLine.arguments.dropFirst().first
    ?? (FileManager.default.fileExists(atPath: rawPath) ? rawPath : outputPath)

guard let image = NSImage(contentsOfFile: inputPath),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.bitmapData else {
    fputs("remove-icon-label: failed to load \(inputPath)\n", stderr)
    exit(1)
}

let width = rep.pixelsWide
let height = rep.pixelsHigh
let bytesPerRow = rep.bytesPerRow

func pixel(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    let offset = y * bytesPerRow + x * 4
    return (data[offset], data[offset + 1], data[offset + 2])
}

func setPixel(_ x: Int, _ y: Int, r: UInt8, g: UInt8, b: UInt8) {
    let offset = y * bytesPerRow + x * 4
    data[offset] = r
    data[offset + 1] = g
    data[offset + 2] = b
}

func paperColor(at x: Int) -> (UInt8, UInt8, UInt8) {
    let clampedX = min(max(0, x), width - 1)
    let sampleRows = [388, 394, 400]
    var samples: [(UInt8, UInt8, UInt8)] = []

    for y in sampleRows where y < height {
        let sample = pixel(clampedX, y)
        let avg = (Int(sample.r) + Int(sample.g) + Int(sample.b)) / 3
        if avg > 120 {
            samples.append(sample)
        }
    }

    if let last = samples.last {
        return last
    }

    return pixel(clampedX, min(394, height - 1))
}

// Replace the dark "Ouplicate" ribbon inside the magnifying-glass documents.
let minX = 232
let maxX = 521
let minY = 398
let maxY = 485

for y in minY...maxY {
    let progress = Double(y - minY) / Double(max(maxY - minY, 1))
    for x in minX...maxX {
        let base = paperColor(at: x)
        let scale = 0.94 + (0.06 * progress)
        let r = UInt8(min(255, Int(Double(base.0) * scale)))
        let g = UInt8(min(255, Int(Double(base.1) * scale)))
        let b = UInt8(min(255, Int(Double(base.2) * scale)))
        setPixel(x, y, r: r, g: g, b: b)
    }
}

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("remove-icon-label: failed to encode PNG\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try png.write(to: outputURL)
fputs("remove-icon-label: wrote \(outputPath) from \(inputPath)\n", stderr)
