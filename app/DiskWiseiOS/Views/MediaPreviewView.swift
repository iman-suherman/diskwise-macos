import AVKit
import Photos
import SwiftUI
import UIKit

/// Full-screen on-device preview: still image or playable video via PhotoKit.
struct MediaPreviewView: View {
    let assetID: String
    var isVideo: Bool = false
    var title: String = "Preview"

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var loadFailed = false
    @State private var imageRequestID: PHImageRequestID?
    @State private var videoRequestID: PHImageRequestID?

    private static let imageManager = PHCachingImageManager()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear(perform: load)
        .onDisappear(perform: teardown)
    }

    @ViewBuilder
    private var content: some View {
        if isVideo, let player {
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .bottom)
                .onAppear { player.play() }
        } else if let image {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if loadFailed {
            ContentUnavailableView(
                "Preview unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("This item could not be loaded from Photos.")
            )
            .foregroundStyle(.white)
        } else {
            ProgressView()
                .tint(.white)
                .controlSize(.large)
        }
    }

    private func load() {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else {
            loadFailed = true
            return
        }

        if asset.mediaType == .video {
            loadVideo(asset)
        } else {
            loadImage(asset)
        }
    }

    private func loadImage(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let target = CGSize(
            width: max(asset.pixelWidth, 1),
            height: max(asset.pixelHeight, 1)
        )
        imageRequestID = Self.imageManager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            Task { @MainActor in
                if let result {
                    self.image = result
                } else if (info?[PHImageResultIsDegradedKey] as? Bool) != true {
                    self.loadFailed = true
                }
            }
        }
    }

    private func loadVideo(_ asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        videoRequestID = Self.imageManager.requestPlayerItem(
            forVideo: asset,
            options: options
        ) { item, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            Task { @MainActor in
                if let item {
                    let avPlayer = AVPlayer(playerItem: item)
                    self.player = avPlayer
                } else {
                    self.loadFailed = true
                }
            }
        }
    }

    private func teardown() {
        player?.pause()
        player = nil
        if let imageRequestID {
            Self.imageManager.cancelImageRequest(imageRequestID)
            self.imageRequestID = nil
        }
        if let videoRequestID {
            Self.imageManager.cancelImageRequest(videoRequestID)
            self.videoRequestID = nil
        }
    }
}
