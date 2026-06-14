import SwiftUI

struct DiskWiseMarkdownText: View {
    let text: String
    var font: Font = .body
    var foregroundStyle: Color? = nil

    private var displayText: String {
        ChatMessageFormatter.formatForDisplay(text)
    }

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: displayText,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                styledText(Text(attributed))
            } else if let attributed = try? AttributedString(
                markdown: displayText,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            ) {
                styledText(Text(attributed))
            } else {
                styledText(Text(displayText))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func styledText(_ text: Text) -> some View {
        if let foregroundStyle {
            text
                .font(font)
                .foregroundStyle(foregroundStyle)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            text
                .font(font)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}
