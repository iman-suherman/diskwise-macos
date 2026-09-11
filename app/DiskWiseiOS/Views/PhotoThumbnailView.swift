import Photos
import SwiftUI
import UIKit

/// Loads an on-device PhotoKit thumbnail for a library asset local identifier.
struct PhotoThumbnailView: View {
    let assetID: String
    var isVideo: Bool = false
    var side: CGFloat = 52

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    private static let imageManager = PHCachingImageManager()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.18))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: isVideo ? "film" : "photo")
                    .font(.system(size: side * 0.32))
                    .foregroundStyle(.secondary)
            }

            if isVideo {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(4)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
        .onAppear(perform: requestThumbnail)
        .onDisappear(perform: cancelRequest)
        .onChange(of: assetID) { _, _ in
            cancelRequest()
            image = nil
            requestThumbnail()
        }
    }

    private func requestThumbnail() {
        if ProcessInfo.processInfo.environment["DISKWISE_DEMO"] == "1" {
            return
        }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else { return }

        let scale = UIScreen.main.scale
        let pixel = CGSize(width: side * scale, height: side * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        requestID = Self.imageManager.requestImage(
            for: asset,
            targetSize: pixel,
            contentMode: .aspectFill,
            options: options
        ) { result, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            if let result {
                Task { @MainActor in
                    self.image = result
                }
            }
        }
    }

    private func cancelRequest() {
        if let requestID {
            Self.imageManager.cancelImageRequest(requestID)
            self.requestID = nil
        }
    }
}
