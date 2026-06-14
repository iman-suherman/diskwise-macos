import SwiftUI
import WebKit

enum DiskWiseMarkdownFormat {
    case chat
    case memoryInsight
    case memoryChat
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
        case .memoryChat:
            return ChatMessageFormatter.formatMemoryChatForDisplay(text)
        }
    }

    private var blocks: [String] {
        switch format {
        case .chat:
            return [displayText]
        case .memoryInsight:
            return ChatMessageFormatter.memoryInsightBlocks(text)
        case .memoryChat:
            return ChatMessageFormatter.memoryChatBlocks(text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: format == .memoryInsight || format == .memoryChat ? 14 : 0) {
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
        let lineSpacing: CGFloat = format == .memoryInsight || format == .memoryChat ? 6 : 4
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

struct DiskWiseHTMLMarkdownView: View {
    let text: String
    var format: DiskWiseMarkdownFormat = .memoryInsight
    var isActive: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 120

    var body: some View {
        Group {
            if isActive {
                DiskWiseHTMLMarkdownWebView(
                    html: htmlDocument,
                    contentHeight: $contentHeight
                )
                .frame(height: max(contentHeight, 40))
            } else if !text.isEmpty {
                DiskWiseMarkdownText(text: text, font: .body, format: format)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var htmlDocument: String {
        switch format {
        case .memoryInsight:
            return ChatMessageFormatter.memoryInsightHTMLDocument(
                from: text,
                isDark: colorScheme == .dark
            )
        case .chat:
            let markdown = ChatMessageFormatter.formatForDisplay(text)
            return ChatMessageFormatter.memoryInsightHTMLDocument(
                from: markdown,
                isDark: colorScheme == .dark
            )
        case .memoryChat:
            let markdown = ChatMessageFormatter.formatMemoryChatForDisplay(text)
            return ChatMessageFormatter.memoryInsightHTMLDocument(
                from: markdown,
                isDark: colorScheme == .dark
            )
        }
    }
}

private struct DiskWiseHTMLMarkdownWebView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.contentHeight = $contentHeight
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        if html.isEmpty {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var contentHeight: Binding<CGFloat>
        var lastHTML: String?

        init(contentHeight: Binding<CGFloat>) {
            self.contentHeight = contentHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
                guard let self else { return }
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self.contentHeight.wrappedValue = height + 8
                    }
                } else if let height = result as? Double, height > 0 {
                    DispatchQueue.main.async {
                        self.contentHeight.wrappedValue = CGFloat(height) + 8
                    }
                }
            }
        }
    }
}
