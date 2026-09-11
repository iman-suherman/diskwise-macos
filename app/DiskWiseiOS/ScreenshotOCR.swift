import Photos
import UIKit
import Vision

/// On-device Vision OCR for screenshot labeling. Never uploads image bytes.
enum ScreenshotOCR {
    private static let imageManager = PHCachingImageManager()

    static func recognizedText(assetID: String, maxCharacters: Int = 800) async -> String {
        guard let image = await requestImage(assetID: assetID) else { return "" }
        guard let cgImage = image.cgImage ?? renderedCGImage(from: image) else { return "" }

        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return ""
            }
            let lines = (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            let joined = lines.joined(separator: "\n")
            if joined.count <= maxCharacters {
                return joined
            }
            return String(joined.prefix(maxCharacters))
        }.value
    }

    private static func requestImage(assetID: String) async -> UIImage? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.version = .current

        return await withCheckedContinuation { continuation in
            var resumed = false
            let finish: (UIImage?) -> Void = { image in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: image)
            }
            imageManager.requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, info in
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                if cancelled {
                    finish(nil)
                    return
                }
                guard let data, let image = UIImage(data: data) else {
                    finish(nil)
                    return
                }
                finish(downsampled(image, maxDimension: 800))
            }
        }
    }
}

private func downsampled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
    let size = image.size
    let longest = max(size.width, size.height)
    guard longest > maxDimension, longest > 0 else { return image }
    let scale = maxDimension / longest
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: target)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
}

private func renderedCGImage(from image: UIImage) -> CGImage? {
    let renderer = UIGraphicsImageRenderer(size: image.size)
    return renderer.image { _ in
        image.draw(at: .zero)
    }.cgImage
}
