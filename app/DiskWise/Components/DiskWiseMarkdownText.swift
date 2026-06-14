import SwiftUI

enum DiskWiseMarkdownFormat {
    case chat
    case memoryInsight
}

struct DiskWiseMarkdownText: View {
    let text: String
    var font: Font = .body
    var foregroundStyle: Color? = nil
    var format: DiskWiseMarkdownFormat = .chat

    private var displayText: String {
        switch format {
        case .chat:
            return ChatMessageFormatter.formatForDisplay(text)
        case .memoryInsight:
            return ChatMessageFormatter.formatMemoryInsightForDisplay(text)
        }
    }

    private var blocks: [String] {
        switch format {
        case .chat:
            return [displayText]
        case .memoryInsight:
            return ChatMessageFormatter.memoryInsightBlocks(text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: format == .memoryInsight ? 14 : 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                markdownBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func markdownBlock(_ block: String) -> some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: block,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                styledText(Text(attributed))
            } else if let attributed = try? AttributedString(
                markdown: block,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                styledText(Text(attributed))
            } else {
                styledText(Text(block))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func styledText(_ text: Text) -> some View {
        let lineSpacing: CGFloat = format == .memoryInsight ? 6 : 4
        if let foregroundStyle {
            text
                .font(font)
                .foregroundStyle(foregroundStyle)
                .lineSpacing(lineSpacing)
                .textSelection(.enabled)
        } else {
            text
                .font(font)
                .lineSpacing(lineSpacing)
                .textSelection(.enabled)
        }
    }
}
