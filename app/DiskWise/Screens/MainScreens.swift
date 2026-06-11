import SwiftUI
import DuplicateKit
import CleanupKit
import DatabaseKit

struct DuplicatesView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var selectedPreview: CleanupPreview?

    private var totalReclaimable: Int64 {
        viewModel.duplicateGroups.reduce(0) { $0 + $1.reclaimableSize }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if viewModel.duplicateGroups.isEmpty {
                    ContentUnavailableView(
                        "No duplicates found",
                        systemImage: "doc.on.doc",
                        description: Text(viewModel.hasScanData
                            ? "Your scanned drive has no duplicate file groups."
                            : "Scan a drive to detect duplicate files.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(viewModel.duplicateGroups) { group in
                        DuplicateGroupCard(group: group) {
                            selectedPreview = viewModel.previewCleanup(for: group)
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(item: $selectedPreview) { preview in
            CleanupPreviewSheet(preview: preview) {
                viewModel.executeCleanup(preview: preview)
                selectedPreview = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duplicate Files")
                .font(.largeTitle.bold())

            if totalReclaimable > 0 {
                Text("\(DiskWiseFormatters.bytes.string(fromByteCount: totalReclaimable)) reclaimable across \(viewModel.duplicateGroups.count) groups")
                    .font(.title3)
                    .foregroundStyle(.orange)
            } else {
                Text("Review duplicate groups and safely remove extra copies")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let onCleanup: () -> Void

    private var displayName: String {
        if let first = group.files.first {
            return URL(fileURLWithPath: first.path).lastPathComponent
        }
        return group.fingerprint
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.headline)
                        Text("\(group.files.count) copies · \(DiskWiseFormatters.bytes.string(fromByteCount: group.reclaimableSize)) reclaimable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Keep Newest") {
                        onCleanup()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.files.prefix(4), id: \.path) { file in
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(file.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if group.files.count > 4 {
                        Text("+ \(group.files.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AskDiskWiseView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private let suggestedQuestions = [
        "What is consuming most of my disk?",
        "Can I safely remove anything?",
        "Why is my SSD almost full?",
        "Find old videos I haven't watched.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ask DiskWise")
                                .font(.largeTitle.bold())
                            Text("Get storage insights powered by your scan data")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.aiResponses.isEmpty {
                            suggestedQuestionsSection
                        }

                        ForEach(viewModel.aiResponses) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(28)
                }
                .onChange(of: viewModel.aiResponses.count) { _, _ in
                    if let last = viewModel.aiResponses.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Ask about your storage…", text: $viewModel.aiQuestion)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.askAI(question: viewModel.aiQuestion)
                    }

                Button {
                    viewModel.askAI(question: viewModel.aiQuestion)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.aiQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
    }

    private var suggestedQuestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try asking:")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(suggestedQuestions, id: \.self) { question in
                    Button {
                        viewModel.askAI(question: question)
                    } label: {
                        Text(question)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.text)
                .font(.body)
                .padding(14)
                .background(
                    message.role == .user
                        ? Color.accentColor.opacity(0.15)
                        : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

struct CleanupPreviewSheet: View {
    let preview: CleanupPreview
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleanup Preview")
                .font(.title.bold())
            Text("\(preview.items.count) files will move to Trash (\(DiskWiseFormatters.bytes.string(fromByteCount: preview.totalBytes))).")
                .foregroundStyle(.secondary)
            List(preview.items) { item in
                Text(item.path).font(.caption)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Move To Trash", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }
}

extension CleanupPreview: Identifiable {
    public var id: String {
        items.map(\.path).joined(separator: "|")
    }
}
