import AppKit
import DatabaseKit
import DuplicateKit
import SwiftUI

struct DuplicateGroupReviewSheet: View {
    let group: DuplicateGroup
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var files: [FileRecord] = []
    @State private var keepPath: String = ""
    @State private var selectedPath: String = ""
    @State private var previewItem: FilePreviewItem?
    @State private var dragOffset: CGFloat = 0
    @State private var failureMessage: String?
    @State private var showFailureAlert = false

    private var keepFile: FileRecord? {
        files.first { $0.path == keepPath }
    }

    private var selectedFile: FileRecord? {
        files.first { $0.path == selectedPath } ?? keepFile ?? files.first
    }

    private var extras: [FileRecord] {
        files.filter { $0.path != keepPath }
    }

    private var isImageGroup: Bool {
        files.contains(where: \.isImageFile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if files.count < 2 {
                ContentUnavailableView(
                    files.isEmpty ? "No copies left" : "Only one copy left",
                    systemImage: "doc.on.doc",
                    description: Text("This duplicate group is already cleaned up.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                filmstrip
                previewPane
                copyActions
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 560)
        .onAppear(perform: load)
        .alert("Could not move to Trash", isPresented: $showFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage ?? "DiskWise could not move this file to Trash.")
        }
        .sheet(item: $previewItem) { item in
            FilePreviewSheet(item: item)
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            trashSelectedExtra()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            markSelectedAsKeep()
            return .handled
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isImageGroup ? "Pick the best photo" : "Pick the copy to keep")
                .font(.title.bold())
            Text("Star the best copy, then swipe extras left to Trash. Nothing is deleted permanently.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(files, id: \.path) { file in
                    Button {
                        selectedPath = file.path
                        dragOffset = 0
                    } label: {
                        VStack(spacing: 6) {
                            FileThumbnailView(path: file.path, cornerRadius: 10)
                                .frame(width: 96, height: 96)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(borderColor(for: file), lineWidth: 3)
                                }
                                .overlay(alignment: .topTrailing) {
                                    if file.path == keepPath {
                                        Image(systemName: "star.fill")
                                            .font(.caption)
                                            .padding(4)
                                            .background(.green, in: Circle())
                                            .foregroundStyle(.white)
                                            .offset(x: 4, y: -4)
                                    }
                                }
                            Text(file.path == keepPath ? "Keep" : "Copy")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(file.path == keepPath ? .green : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var previewPane: some View {
        if let file = selectedFile {
            VStack(alignment: .leading, spacing: 12) {
                FileThumbnailView(path: file.path, cornerRadius: 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .offset(x: file.path == keepPath ? 0 : dragOffset)
                    .rotationEffect(.degrees(file.path == keepPath ? 0 : Double(dragOffset) / 18))
                    .overlay(alignment: .topTrailing) {
                        if dragOffset < -40, file.path != keepPath {
                            Label("Trash", systemImage: "trash.fill")
                                .padding(8)
                                .background(.red.opacity(0.9), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(12)
                        } else if dragOffset > 40 {
                            Label("Keep this", systemImage: "star.fill")
                                .padding(8)
                                .background(.green.opacity(0.9), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(12)
                        }
                    }
                    .gesture(extraDragGesture)
                    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: dragOffset)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(fileURLWithPath: file.path).lastPathComponent)
                            .font(.headline)
                        Text(file.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(DiskWiseFormatters.bytes.string(fromByteCount: file.size))
                        .font(.subheadline.weight(.semibold))
                    Button {
                        previewItem = FilePreviewItem(path: file.path)
                    } label: {
                        Label(file.isVideoFile ? "Play" : "View", systemImage: file.isVideoFile ? "play.fill" : "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Reveal in Finder")
                }
            }
        }
    }

    @ViewBuilder
    private var copyActions: some View {
        if let file = selectedFile, file.path == keepPath {
            Label("This is the copy DiskWise will keep. Swipe another thumbnail to Trash extras.", systemImage: "star.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        } else {
            HStack(spacing: 12) {
                Button {
                    trashSelectedExtra()
                } label: {
                    Label("Trash this copy", systemImage: "trash.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)

                Button {
                    markSelectedAsKeep()
                } label: {
                    Label("Keep this one instead", systemImage: "star.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Close") { dismiss() }
            Spacer()
            if extras.count >= 1 {
                Button {
                    let preview = viewModel.previewCleanup(for: group, keepingPath: keepPath)
                    let result = viewModel.executeCleanup(preview: preview, revealTrash: true)
                    if result.movedCount > 0 {
                        dismiss()
                    } else if let first = result.failures.first {
                        failureMessage = "\(URL(fileURLWithPath: first.path).lastPathComponent): \(first.reason)"
                        showFailureAlert = true
                    }
                } label: {
                    Label("Trash the other \(extras.count) cop\(extras.count == 1 ? "y" : "ies")", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var extraDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard selectedFile?.path != keepPath else {
                    dragOffset = 0
                    return
                }
                if value.translation.width < -120 {
                    trashSelectedExtra()
                } else if value.translation.width > 120 {
                    markSelectedAsKeep()
                } else {
                    dragOffset = 0
                }
            }
    }

    private func borderColor(for file: FileRecord) -> Color {
        if file.path == selectedPath { return .orange }
        if file.path == keepPath { return .green }
        return .clear
    }

    private func markSelectedAsKeep() {
        guard let file = selectedFile else { return }
        keepPath = file.path
        dragOffset = 0
    }

    private func trashSelectedExtra() {
        guard let file = selectedFile, file.path != keepPath else {
            dragOffset = 0
            return
        }
        let result = viewModel.trashFiles([file])
        if result.movedCount > 0 {
            files.removeAll { $0.path == file.path }
            if files.count < 2 {
                dismiss()
                return
            }
            selectedPath = keepPath
            dragOffset = 0
        } else if let first = result.failures.first {
            failureMessage = "\(URL(fileURLWithPath: first.path).lastPathComponent): \(first.reason)"
            showFailureAlert = true
            dragOffset = 0
        }
    }

    private func load() {
        let members = viewModel.files(for: group)
        let ranked = DuplicateCopyRanker.ranked(members)
        files = ranked
        keepPath = ranked.first?.path ?? ""
        selectedPath = extras.first?.path ?? keepPath
        dragOffset = 0
    }
}
