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

                if !viewModel.duplicateGroups.isEmpty {
                    cleanupActionBar
                }

                if viewModel.isFindingDuplicates {
                    duplicateScanInProgress
                } else if viewModel.duplicateGroups.isEmpty {
                    duplicatesEmptyState
                } else {
                    howToCleanHint

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
            CleanupPreviewSheet(preview: preview) { result in
                if result.movedCount > 0 {
                    selectedPreview = nil
                }
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
            } else if viewModel.isFindingDuplicates {
                Text("Still checking your drive for duplicate files…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Run duplicate detection from this tab after identifying disk usage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cleanupActionBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to free up space")
                    .font(.headline)
                Text("DiskWise keeps one copy per group and moves the rest to Trash. Empty Trash when you're sure.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                selectedPreview = viewModel.previewAllDuplicatesCleanup()
            } label: {
                Label("Move All Duplicates to Trash", systemImage: "trash.fill")
                    .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
        }
        .padding(18)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var howToCleanHint: some View {
        Label("Use Move to Trash on any group below to remove extra copies safely.", systemImage: "hand.tap.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var duplicatesEmptyState: some View {
        if viewModel.hasScanData {
            ContentUnavailableView {
                Label("No duplicates found yet", systemImage: "doc.on.doc")
            } description: {
                Text("Duplicate detection runs separately from the main identify → analyze workflow. Scan here when you want to find extra copies.")
            } actions: {
                Button(viewModel.isFindingDuplicates ? "Finding…" : "Find Duplicates") {
                    viewModel.scanForDuplicates()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isFindingDuplicates)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
        } else {
            ContentUnavailableView(
                "Identify disk usage first",
                systemImage: "externaldrive",
                description: Text("Select a drive and run Phase 1 (Identify usage) from the sidebar. Then return here to find duplicates.")
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private var duplicateScanInProgress: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress = viewModel.duplicateScanProgress {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(progress.level.label, systemImage: "doc.on.doc")
                            .font(.headline)
                        Text(progress.level.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ProgressView(value: progress.levelFraction)
                        Text("\(progress.processedCount.formatted()) of \(progress.totalCount.formatted()) largest files checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Limit: \(viewModel.appSettings.duplicateScanFileLimit.formatted()) files · adjust in Settings (⌘,)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(progress.currentPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                GroupBox {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing duplicate scan…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !viewModel.duplicateGroups.isEmpty {
                Text("Found so far")
                    .font(.headline)
                ForEach(viewModel.duplicateGroups) { group in
                    DuplicateGroupCard(group: group) {
                        selectedPreview = viewModel.previewCleanup(for: group)
                    }
                }
            } else {
                Text("Fingerprinting files can take several minutes on large drives. You can review storage in Overview while this runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
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

    private var extraCopyCount: Int {
        max(0, group.fileCount - 1)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName)
                            .font(.headline)
                        Text("\(group.fileCount) copies · keep 1 · remove \(extraCopyCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(DiskWiseFormatters.bytes.string(fromByteCount: group.reclaimableSize)) reclaimable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
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
                    if group.fileCount > 4 {
                        Text("+ \(group.fileCount - 4) more")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                Button(action: onCleanup) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Move \(extraCopyCount) Duplicate\(extraCopyCount == 1 ? "" : "s") to Trash")
                                .font(.headline)
                            Text("Keeps one copy · you can empty Trash later")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        Image(systemName: "trash.fill")
                            .font(.title3)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AskDiskWiseView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private var suggestedQuestions: [String] {
        viewModel.aiSuggestedQuestions.isEmpty
            ? [
                "What is consuming most of my disk?",
                "Can I safely remove anything?",
                "Why is my SSD almost full?",
                "Find old videos I haven't watched.",
            ]
            : viewModel.aiSuggestedQuestions
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Ask DiskWise")
                                        .font(.largeTitle.bold())
                                    Text(viewModel.aiProviderStatus.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    aiProviderBadge
                                }

                                Spacer()

                                Button {
                                    viewModel.startNewAIChatSession()
                                } label: {
                                    Label("New Session", systemImage: "plus.message")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isChatBusy)
                                .help("Clear the chat and start a fresh conversation")
                            }
                        }

                        if viewModel.aiResponses.isEmpty {
                            suggestedQuestionsSection
                        }

                        ForEach(viewModel.aiResponses) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isAITyping {
                            typingIndicator
                                .id("typing-indicator")
                        }
                    }
                    .padding(28)
                }
                .onChange(of: viewModel.aiResponses.count) { _, _ in
                    scrollToLatest(with: proxy)
                }
                .onChange(of: viewModel.aiResponses.map(\.text)) { _, _ in
                    scrollToLatest(with: proxy)
                }
                .onChange(of: viewModel.isAITyping) { _, isTyping in
                    if isTyping {
                        withAnimation {
                            proxy.scrollTo("typing-indicator", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            VStack(spacing: 8) {
                if !viewModel.aiAutocompleteSuggestions.isEmpty {
                    autocompleteSection
                }

                HStack(spacing: 12) {
                    TextField("Ask about your storage…", text: $viewModel.aiQuestion)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            viewModel.askAI(question: viewModel.aiQuestion)
                        }
                        .onChange(of: viewModel.aiQuestion) { _, _ in
                            viewModel.updateAIAutocomplete()
                        }

                    Button {
                        viewModel.askAI(question: viewModel.aiQuestion)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.aiQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChatBusy)
                }
            }
            .padding(16)
        }
    }

    private var isChatBusy: Bool {
        viewModel.isAITyping || viewModel.aiResponses.contains(where: \.isStreaming)
    }

    private var aiProviderBadge: some View {
        Label {
            Text(viewModel.aiProviderStatus.displayName)
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: viewModel.aiProviderStatus.isGenerativeAvailable ? "sparkles" : "text.book.closed")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            viewModel.aiProviderStatus.isGenerativeAvailable
                ? Color.accentColor.opacity(0.12)
                : Color.secondary.opacity(0.12),
            in: Capsule()
        )
        .foregroundStyle(viewModel.aiProviderStatus.isGenerativeAvailable ? Color.accentColor : Color.secondary)
    }

    private var autocompleteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggestions")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(viewModel.aiAutocompleteSuggestions, id: \.self) { suggestion in
                Button {
                    viewModel.aiQuestion = suggestion
                    viewModel.askAI(question: suggestion)
                } label: {
                    Text(suggestion)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typingIndicator: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("DiskWise is thinking…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 60)
        }
    }

    private func scrollToLatest(with proxy: ScrollViewProxy) {
        if let last = viewModel.aiResponses.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
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
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 72)
                bubbleContent
            } else {
                assistantAvatar
                bubbleContent
                Spacer(minLength: 48)
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Text(message.role == .user ? "You" : "DiskWise")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                if message.role == .assistant {
                    if message.isStreaming && message.text.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ChatMarkdownText(text: message.text)
                        if message.isStreaming {
                            StreamingCursor()
                        }
                    }
                } else {
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(bubbleBorder, lineWidth: 1)
            }
        }
        .frame(maxWidth: 560, alignment: message.role == .user ? .trailing : .leading)
    }

    private var assistantAvatar: some View {
        Image(systemName: "sparkles")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28)
            .background(Color.accentColor.opacity(0.12), in: Circle())
            .padding(.top, 18)
    }

    private var bubbleBackground: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(Color.accentColor.opacity(0.14))
            : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }

    private var bubbleBorder: Color {
        message.role == .user
            ? Color.accentColor.opacity(0.18)
            : Color.primary.opacity(0.08)
    }
}

private struct ChatMarkdownText: View {
    let text: String

    var body: some View {
        DiskWiseMarkdownText(text: text, font: .body)
    }
}

private struct StreamingCursor: View {
    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 7, height: 16)
            .opacity(isVisible ? 1 : 0.2)
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: isVisible)
            .onAppear { isVisible.toggle() }
    }
}

struct CleanupPreviewSheet: View {
    let preview: CleanupPreview
    var subject: String = "duplicate file(s)"
    let onConfirm: (CleanupResult) -> Void
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var failureMessage: String?
    @State private var showFailureAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Confirm cleanup", systemImage: "trash.fill")
                .font(.title.bold())
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(preview.items.count) \(subject) will move to Trash")
                    .font(.headline)
                Text("Frees \(DiskWiseFormatters.bytes.string(fromByteCount: preview.totalBytes)). Nothing is deleted permanently — empty Trash later when you're sure.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            List(preview.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(URL(fileURLWithPath: item.path).lastPathComponent)
                        .font(.subheadline.weight(.medium))
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    let result = viewModel.executeCleanup(preview: preview, revealTrash: true)
                    if result.movedCount > 0 {
                        onConfirm(result)
                        dismiss()
                    } else if let first = result.failures.first {
                        failureMessage = "\(URL(fileURLWithPath: first.path).lastPathComponent): \(first.reason)"
                        showFailureAlert = true
                    } else {
                        failureMessage = "No files were moved to Trash."
                        showFailureAlert = true
                    }
                } label: {
                    Label("Move to Trash", systemImage: "trash.fill")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 460)
        .alert("Could not move to Trash", isPresented: $showFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage ?? "DiskWise could not move these files to Trash.")
        }
    }
}

extension CleanupPreview: Identifiable {
    public var id: String {
        items.map(\.path).joined(separator: "|")
    }
}
