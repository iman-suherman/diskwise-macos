import AVKit
import Photos
import PhotosKit
import SwiftUI
import UIKit

/// Full-screen on-device preview: still image or playable video via PhotoKit.
/// Images are fitted to the screen (pinch / double-tap to zoom) so chrome stays reachable.
struct MediaPreviewView: View {
    let assetID: String
    var isVideo: Bool = false
    var title: String = "Preview"
    var subtitle: String?
    var onDelete: (() async -> Bool)?

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var loadFailed = false
    @State private var imageRequestID: PHImageRequestID?
    @State private var videoRequestID: PHImageRequestID?
    @State private var confirmDelete = false
    @State private var isDeleting = false

    private static let imageManager = PHCachingImageManager()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
                if isDeleting {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if onDelete != nil {
                        Button("Delete", role: .destructive) {
                            confirmDelete = true
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                    if onDelete != nil {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(isDeleting)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.78))
            }
            .confirmationDialog(
                "Move this item to Recently Deleted?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Move to Recently Deleted", role: .destructive) {
                    Task {
                        isDeleting = true
                        let ok = await onDelete?() ?? false
                        isDeleting = false
                        if ok { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can recover it in Photos for about 30 days. DiskWise never empties Recently Deleted.")
            }
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
            FittedZoomableImage(image: image)
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
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        let scale = UIScreen.main.scale
        let screen = UIScreen.main.bounds.size
        // Cap at ~2× the screen so pinch-zoom stays sharp without native-pixel overflow.
        let target = CGSize(
            width: max(screen.width * scale * 2, 1),
            height: max(screen.height * scale * 2, 1)
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

private struct FittedZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var gestureScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale * gestureScale)
                .offset(offset)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            gestureScale = value.magnification
                        }
                        .onEnded { value in
                            scale = max(1, min(scale * value.magnification, 4))
                            gestureScale = 1
                            if scale == 1 { offset = .zero }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1 {
                            scale = 1
                            offset = .zero
                        } else {
                            scale = 2
                        }
                    }
                }
        }
    }
}
