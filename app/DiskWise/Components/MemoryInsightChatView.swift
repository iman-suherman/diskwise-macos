import AIKit
import SwiftUI

struct MemoryInsightChatView: View {
    let report: MemoryAnalysisReport
    @ObservedObject var monitor: MemoryAnalyzerMonitor

    private var suggestedQuestions: [String] {
        monitor.suggestedMemoryQuestions(for: report)
    }

    private var isChatBusy: Bool {
        monitor.isMemoryChatTyping || monitor.memoryChatResponses.contains(where: \.isStreaming)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Ask about memory", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !monitor.memoryChatResponses.isEmpty {
                    Button("Clear") {
                        monitor.clearMemoryChat()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(isChatBusy)
                }
            }

            if monitor.memoryChatResponses.isEmpty {
                suggestedQuestionsSection
            }

            ForEach(monitor.memoryChatResponses) { message in
                MemoryChatBubble(message: message)
            }

            HStack(spacing: 10) {
                TextField("Ask a follow-up question…", text: $monitor.memoryChatQuestion)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        monitor.askMemoryChat(question: monitor.memoryChatQuestion)
                    }

                Button {
                    monitor.askMemoryChat(question: monitor.memoryChatQuestion)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(
                    monitor.memoryChatQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isChatBusy
                        || monitor.isStreamingAISummary
                )
            }
        }
        .padding(.top, 4)
    }

    private var suggestedQuestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try asking:")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(suggestedQuestions, id: \.self) { question in
                    Button {
                        monitor.askMemoryChat(question: question)
                    } label: {
                        Text(question)
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isChatBusy || monitor.isStreamingAISummary)
                }
            }
        }
    }
}

private struct MemoryChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 48)
                bubbleContent
            } else {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                    .padding(.top, 14)
                bubbleContent
                Spacer(minLength: 24)
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "DiskWise")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if message.role == .assistant {
                    if message.isStreaming && message.text.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        DiskWiseMarkdownText(text: message.text, font: .callout)
                    }
                } else {
                    Text(message.text)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(bubbleBorder, lineWidth: 1)
            }
        }
        .frame(maxWidth: 480, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleBackground: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(Color.accentColor.opacity(0.12))
            : AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    }

    private var bubbleBorder: Color {
        message.role == .user
            ? Color.accentColor.opacity(0.16)
            : Color.primary.opacity(0.08)
    }
}
