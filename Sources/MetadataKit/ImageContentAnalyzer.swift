import Foundation
import ImageIO
import Vision

public enum ImageContentAnalyzer {
    public static func recognizedText(at url: URL, maxCharacters: Int = 800) -> String {
        guard url.isFileURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { observation in
            observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }

        let joined = lines.joined(separator: "\n")
        if joined.count <= maxCharacters {
            return joined
        }
        return String(joined.prefix(maxCharacters))
    }

    public static func pixelCount(at url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return max(0, width) * max(0, height)
    }
}
