import AppKit
import AVKit
import DatabaseKit
import QuickLookThumbnailing
import SwiftUI

struct FilePreviewItem: Identifiable {
    let id: String
    let url: URL
    let isVideo: Bool
    let isImage: Bool

    init(path: String) {
        url = URL(fileURLWithPath: path)
        id = path
        isVideo = VideoFileRules.isVideoFile(path)
        isImage = ImageFileRules.isImageFile(path)
    }
}

struct FilePreviewButton: View {
    let path: String
    @State private var item: FilePreviewItem?

    private var isVideo: Bool { VideoFileRules.isVideoFile(path) }

    var body: some View {
        Button {
            item = FilePreviewItem(path: path)
        } label: {
            Image(systemName: isVideo ? "play.circle.fill" : "eye")
        }
        .buttonStyle(.borderless)
        .help(isVideo ? "Play" : "View")
        .sheet(item: $item) { preview in
            FilePreviewSheet(item: preview)
        }
    }
}

struct FilePreviewSheet: View {
    let item: FilePreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                .buttonStyle(.borderless)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ZStack {
                Color.black.opacity(0.92)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear(perform: load)
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.isVideo, let player {
            VideoPlayer(player: player)
                .onAppear { player.play() }
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(12)
        } else if loadFailed {
            ContentUnavailableView(
                "Preview unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Open the file in Finder instead.")
            )
            .foregroundStyle(.white)
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
    }

    private func load() {
        if item.isVideo {
            let avPlayer = AVPlayer(url: item.url)
            player = avPlayer
            return
        }
        if item.isImage {
            image = NSImage(contentsOf: item.url)
            loadFailed = image == nil
            return
        }
        NSWorkspace.shared.open(item.url)
        dismiss()
    }
}

struct FileThumbnailView: View {
    let path: String
    var cornerRadius: CGFloat = 10

    @State private var image: NSImage?

    private var isVideo: Bool { VideoFileRules.isVideoFile(path) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: isVideo ? "film" : ImageFileRules.isImageFile(path) ? "photo" : "doc")
                    .foregroundStyle(.secondary)
            }

            if isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear(perform: loadThumbnail)
        .onChange(of: path) { _, _ in
            image = nil
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let url = URL(fileURLWithPath: path)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 360, height: 360),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let thumbnail = representation?.nsImage else { return }
            DispatchQueue.main.async {
                image = thumbnail
            }
        }
    }
}
