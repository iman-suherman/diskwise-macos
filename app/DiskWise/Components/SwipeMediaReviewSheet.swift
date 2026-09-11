import AIKit
import CleanupKit
import DatabaseKit
import MetadataKit
import SwiftUI

struct SwipeMediaReviewSheet: View {
    let title: String
    let subtitle: String
    let files: [FileRecord]
    var showsScreenshotInsights: Bool = false
    var onTrash: (FileRecord) -> CleanupResult
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var remaining: [FileRecord]
    @State private var insights: [String: ScreenshotInsight] = [:]
    @State private var dragOffset: CGFloat = 0
    @State private var keptCount = 0
    @State private var trashedCount = 0
    @State private var failureMessage: String?
    @State private var showFailureAlert = false

    init(
        title: String,
        subtitle: String,
        files: [FileRecord],
        showsScreenshotInsights: Bool = false,
        onTrash: @escaping (FileRecord) -> CleanupResult,
        onFinished: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.files = files
        self.showsScreenshotInsights = showsScreenshotInsights
        self.onTrash = onTrash
        self.onFinished = onFinished
        let sorted = showsScreenshotInsights
            ? files.sorted { lhs, rhs in
                ScreenshotInsightEngine.insight(for: lhs).keepScore
                    < ScreenshotInsightEngine.insight(for: rhs).keepScore
            }
            : files
        _remaining = State(initialValue: sorted)
    }

    private var current: FileRecord? { remaining.first }
    private var progressLabel: String {
        let total = files.count
        let done = keptCount + trashedCount
        return "\(min(done + (remaining.isEmpty ? 0 : 1), total)) of \(total)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let current {
                card(for: current)
                    .offset(x: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset) / 18))
                    .gesture(dragGesture)
                    .animation(.spring(response: 0.28, dampingFraction: 0.86), value: dragOffset)
                    .animation(.easeInOut(duration: 0.2), value: current.path)
            } else {
                finishedState
            }

            if current != nil {
                controls
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 620)
        .onAppear { analyzeUpcoming() }
        .onChange(of: remaining.first?.path) { _, _ in
            dragOffset = 0
            analyzeUpcoming()
        }
        .alert("Could not move to Trash", isPresented: $showFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage ?? "DiskWise could not move this file to Trash.")
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            trashCurrent()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            keepCurrent()
            return .handled
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.title.bold())
                Spacer()
                Text(progressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Swipe left or press ← to Trash · swipe right or press → to keep")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func card(for file: FileRecord) -> some View {
        let insight = insights[file.path] ?? (showsScreenshotInsights ? ScreenshotInsightEngine.insight(for: file) : nil)

        VStack(alignment: .leading, spacing: 14) {
            FileThumbnailView(path: file.path, cornerRadius: 16)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .overlay(alignment: .topLeading) {
                    if let insight {
                        scoreBadge(insight)
                            .padding(12)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    swipeHint
                        .padding(12)
                }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(insight?.label ?? URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.title2.bold())
                    if let insight {
                        Text(insight.reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(file.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text(DiskWiseFormatters.bytes.string(fromByteCount: file.size))
                        .font(.headline)
                    FilePreviewButton(path: file.path)
                }
            }
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(cardBorderColor.opacity(0.7), lineWidth: 3)
        }
    }

    private var swipeHint: some View {
        Group {
            if dragOffset < -40 {
                Label("Trash", systemImage: "trash.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
            } else if dragOffset > 40 {
                Label("Keep", systemImage: "checkmark")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    private var cardBorderColor: Color {
        if dragOffset < -40 { return .red }
        if dragOffset > 40 { return .green }
        return .clear
    }

    private func scoreBadge(_ insight: ScreenshotInsight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(insight.keepScore)")
                .font(.title.bold())
                .monospacedDigit()
            Text(insight.action.label)
                .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(scoreColor(insight.action).opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.white)
        .help("Keep score \(insight.keepScore) of 100")
    }

    private func scoreColor(_ action: ScreenshotKeepAction) -> Color {
        switch action {
        case .trash: return .orange
        case .review: return .blue
        case .keep: return .green
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                trashCurrent()
            } label: {
                Label("Trash", systemImage: "trash.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button {
                keepCurrent()
            } label: {
                Label("Keep", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    private var finishedState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("All done", systemImage: "checkmark.circle.fill")
            } description: {
                Text("Kept \(keptCount) · moved \(trashedCount) to Trash.")
            }
            HStack {
                Spacer()
                Button("Close") {
                    onFinished()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation.width
            }
            .onEnded { value in
                if value.translation.width < -120 {
                    trashCurrent()
                } else if value.translation.width > 120 {
                    keepCurrent()
                } else {
                    dragOffset = 0
                }
            }
    }

    private func keepCurrent() {
        guard !remaining.isEmpty else { return }
        remaining.removeFirst()
        keptCount += 1
        dragOffset = 0
    }

    private func trashCurrent() {
        guard let file = remaining.first else { return }
        let result = onTrash(file)
        if result.movedCount > 0 {
            remaining.removeFirst()
            trashedCount += 1
            dragOffset = 0
        } else if let first = result.failures.first {
            failureMessage = "\(URL(fileURLWithPath: first.path).lastPathComponent): \(first.reason)"
            showFailureAlert = true
            dragOffset = 0
        } else {
            failureMessage = "No files were moved to Trash."
            showFailureAlert = true
            dragOffset = 0
        }
    }

    private func analyzeUpcoming() {
        guard showsScreenshotInsights else { return }
        let upcoming = Array(remaining.prefix(3))
        for file in upcoming {
            guard insights[file.path] == nil else { continue }
            insights[file.path] = ScreenshotInsightEngine.insight(for: file)
            Task.detached(priority: .utility) {
                let ocr = ImageContentAnalyzer.recognizedText(at: URL(fileURLWithPath: file.path))
                let refined = ScreenshotInsightEngine.insight(for: file, ocrText: ocr)
                await MainActor.run {
                    insights[file.path] = refined
                }
            }
        }
    }
}
