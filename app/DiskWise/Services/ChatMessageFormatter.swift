import AppKit
import Foundation

enum ChatMessageFormatter {
    private static let sectionHeaders = [
        "Summary",
        "Recommendations",
        "Cleanup Suggestions",
        "Top categories",
        "Largest folders",
        "Insights",
        "Next steps",
        "Safe to clean",
        "Review first",
        "Memory overview",
        "Memory under pressure",
        "Current memory state",
        "Current Memory State Analysis",
        "Top consumers",
        "Persistent memory consumers",
        "Persistent Memory Consumers",
        "Optimization tips",
        "Suggested actions",
        "Practical Habits for Efficient Use",
        "Practical habits for efficient use",
        "Better computing habits",
        "Quitting or restarting apps",
        "macOS system services",
    ]

    static func formatForDisplay(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else { return result }

        for header in sectionHeaders {
            result = result.replacingOccurrences(
                of: "(\(NSRegularExpression.escapedPattern(for: header)))(:)?(?=[A-Z0-9])",
                with: "\n\n$1$2\n",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: "(?<=[.!?])\\s*(\(NSRegularExpression.escapedPattern(for: header)))",
                with: "\n\n$1",
                options: .regularExpression
            )
        }

        result = result.replacingOccurrences(
            of: "([0-9]+)\\.([A-Za-z])",
            with: "$1. $2",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "([^\\n])• ",
            with: "$1\n• ",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "([^\\n])- ",
            with: "$1\n- ",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func formatMemoryInsightForDisplay(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else { return result }

        result = result.replacingOccurrences(
            of: "\\s*(#{1,6}\\s+)",
            with: "\n\n$1",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "([.!?])\\s+(#{1,6}\\s+)",
            with: "$1\n\n$2",
            options: .regularExpression
        )

        for header in sectionHeaders {
            result = result.replacingOccurrences(
                of: "(?<!#)\\s*(\(NSRegularExpression.escapedPattern(for: header)))\\s*",
                with: "\n\n$1\n",
                options: .regularExpression
            )
        }

        result = result.replacingOccurrences(
            of: "([.!?])\\s+(-|\\*|•)\\s+",
            with: "$1\n\n$2 ",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "([^\\n])\\s+(-|\\*|•)\\s+",
            with: "$1\n$2 ",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "([.!?])\\s+(\\d+\\.\\s+)",
            with: "$1\n\n$2",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "([.!?])\\s+(?=[A-Z][a-z])",
            with: "$1\n\n",
            options: .regularExpression
        )

        result = formatForDisplay(result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func memoryInsightRenderableMarkdown(_ text: String) -> String {
        var result = formatMemoryInsightForDisplay(text)
        guard !result.isEmpty else { return result }

        for header in sectionHeaders {
            let escaped = NSRegularExpression.escapedPattern(for: header)
            result = result.replacingOccurrences(
                of: "(?m)^\\s*\(escaped)\\s*:?\\s*$",
                with: "## \(header)",
                options: .regularExpression
            )
        }

        result = result.replacingOccurrences(
            of: "(?m)^Tip\\s+(\\d+)\\s*:\\s*",
            with: "### Tip $1: ",
            options: .regularExpression
        )

        result = result.replacingOccurrences(of: "• ", with: "- ")
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func memoryInsightHTMLDocument(from text: String, isDark: Bool) -> String {
        let markdown = memoryInsightRenderableMarkdown(text)
        let body: String

        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            let nsAttributed = NSAttributedString(attributed)
            if nsAttributed.length > 0,
               let data = try? nsAttributed.data(
                from: NSRange(location: 0, length: nsAttributed.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ]
               ),
               let fragment = String(data: data, encoding: .utf8) {
                body = fragment
            } else {
                body = "<pre>\(escapeHTML(markdown))</pre>"
            }
        } else {
            body = "<pre>\(escapeHTML(markdown))</pre>"
        }

        return htmlPage(body: body, isDark: isDark)
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func htmlPage(body: String, isDark: Bool) -> String {
        let textColor = isDark ? "#E8E8ED" : "#1D1D1F"
        let secondaryColor = isDark ? "#A1A1A6" : "#6E6E73"
        let accentColor = isDark ? "#6EA8FE" : "#0066CC"
        let cardColor = isDark ? "#2C2C2E" : "#F5F5F7"
        let borderColor = isDark ? "#3A3A3C" : "#D2D2D7"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root {
            color-scheme: \(isDark ? "dark" : "light");
          }
          html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: \(textColor);
            font: -apple-system-body;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            font-size: 13px;
            line-height: 1.55;
          }
          body { padding: 2px 0; }
          h1, h2, h3, h4 {
            color: \(textColor);
            margin: 1.1em 0 0.45em;
            line-height: 1.25;
            font-weight: 600;
          }
          h2 { font-size: 15px; }
          h3 { font-size: 14px; }
          p { margin: 0.55em 0; color: \(secondaryColor); }
          strong, b { color: \(textColor); font-weight: 600; }
          ul, ol {
            margin: 0.5em 0 0.8em;
            padding-left: 1.25em;
            color: \(secondaryColor);
          }
          li { margin: 0.35em 0; }
          li::marker { color: \(accentColor); }
          code, pre {
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            background: \(cardColor);
            border: 1px solid \(borderColor);
            border-radius: 6px;
          }
          pre {
            white-space: pre-wrap;
            padding: 10px 12px;
            margin: 0.6em 0;
          }
          a { color: \(accentColor); text-decoration: none; }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }

    static func memoryInsightBlocks(_ text: String) -> [String] {
        formatMemoryInsightForDisplay(text)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseMemoryInsight(_ text: String) -> [MemoryInsightSection] {
        let normalized = normalizeMemoryInsightText(text)
        let rawBlocks = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var sections: [MemoryInsightSection] = []
        var currentTitle: String?
        var currentItems: [MemoryInsightItem] = []

        func flushSection() {
            guard currentTitle != nil || !currentItems.isEmpty else { return }
            let title = currentTitle
            sections.append(
                MemoryInsightSection(
                    id: title ?? "section-\(sections.count)",
                    title: title,
                    items: currentItems
                )
            )
            currentTitle = nil
            currentItems = []
        }

        for block in rawBlocks {
            if let heading = parseHeading(block) {
                flushSection()
                currentTitle = heading
                continue
            }

            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if lines.count == 1, let item = parseSingleLineInsight(lines[0]) {
                currentItems.append(item)
                continue
            }

            if lines.count > 1, isSubheading(lines[0]) {
                currentItems.append(.subheading(cleanMarkdown(lines[0])))
                for line in lines.dropFirst() {
                    appendParsedLine(line, to: &currentItems)
                }
                continue
            }

            for line in lines {
                appendParsedLine(line, to: &currentItems)
            }
        }

        flushSection()
        return mergeDuplicateSections(sections)
    }

    private static func appendParsedLine(_ line: String, to items: inout [MemoryInsightItem]) {
        if let item = parseSingleLineInsight(line) {
            items.append(item)
        } else {
            let cleaned = cleanMarkdown(line)
            guard !cleaned.isEmpty else { return }
            items.append(.paragraph(cleaned))
        }
    }

    private static func isSubheading(_ line: String) -> Bool {
        let stripped = cleanMarkdown(line)
        guard !stripped.isEmpty else { return false }
        guard !stripped.hasPrefix("-") else { return false }
        guard stripped.count <= 56 else { return false }
        guard !stripped.contains("avg ") else { return false }
        return !stripped.contains(where: { $0 == "%" })
    }

    private static func cleanMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "\\.\\.", with: ".", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    }

    private static func mergeDuplicateSections(_ sections: [MemoryInsightSection]) -> [MemoryInsightSection] {
        var merged: [MemoryInsightSection] = []
        for section in sections {
            if let last = merged.last,
               let lastTitle = last.title,
               let sectionTitle = section.title,
               lastTitle.caseInsensitiveCompare(sectionTitle) == .orderedSame {
                merged[merged.count - 1] = MemoryInsightSection(
                    id: last.id,
                    title: last.title,
                    items: last.items + section.items
                )
            } else {
                merged.append(section)
            }
        }
        return merged
    }

    private static func normalizeMemoryInsightText(_ text: String) -> String {
        var result = formatMemoryInsightForDisplay(text)

        result = result.replacingOccurrences(
            of: "UseCurrent:",
            with: "Current:",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "Memory Use\\s*Current:",
            with: "Current:",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "([0-9]+)\\.([A-Za-z])",
            with: "$1. $2",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "Tip\\s*(\\d+)\\s*:\\s*",
            with: "\n\nTip $1: ",
            options: .regularExpression
        )

        for header in sectionHeaders {
            let escaped = NSRegularExpression.escapedPattern(for: header)
            result = result.replacingOccurrences(
                of: "(\(escaped))(?=[A-Za-z])",
                with: "$1\n\n",
                options: .regularExpression
            )
        }

        result = result.replacingOccurrences(
            of: "([a-z])([A-Z][a-z]{3,})",
            with: "$1\n$2",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "([^\\n])- \\*\\*",
            with: "$1\n- **",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "\\.\\.+",
            with: ".",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "Trend:\\s*",
            with: "\nTrend: ",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseHeading(_ block: String) -> String? {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("### ") {
            return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("## ") {
            return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("# ") {
            return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let singleLine = trimmed
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard singleLine.count == 1 else { return nil }
        let line = singleLine[0]
        let stripped = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))

        if sectionHeaders.contains(where: { $0.caseInsensitiveCompare(stripped) == .orderedSame }) {
            return stripped
        }

        if stripped.count <= 48,
           stripped == stripped.capitalized || stripped.contains(where: \.isUppercase),
           !stripped.contains(".") {
            return stripped
        }

        return nil
    }

    private static func parseSingleLineInsight(_ line: String) -> MemoryInsightItem? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let tip = parseTip(trimmed) {
            return tip
        }

        if let bullet = parseBullet(trimmed) {
            return bullet
        }

        if let metric = parseMetric(trimmed) {
            return metric
        }

        return nil
    }

    private static func parseTip(_ line: String) -> MemoryInsightItem? {
        let patterns = [
            #"^Tip\s+(\d+)\s*:\s*(.+)$"#,
            #"^(\d+)\.\s+(.+)$"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let numberRange = Range(match.range(at: 1), in: line),
                  let bodyRange = Range(match.range(at: 2), in: line),
                  let number = Int(line[numberRange]) else {
                continue
            }

            let body = String(line[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let dashRange = body.range(of: " — ") {
                let title = String(body[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = String(body[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return .tip(number: number, title: title, body: detail)
            }

            let (title, detail) = splitTitleAndBody(body)
            return .tip(number: number, title: title ?? "Tip \(number)", body: detail)
        }

        return nil
    }

    private static func parseBullet(_ line: String) -> MemoryInsightItem? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("*") else { return nil }

        trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("*") || trimmed.hasPrefix("-") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let content = trimmed
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        if let colonIndex = content.firstIndex(of: ":") {
            let label = String(content[..<colonIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(content[content.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty, !value.isEmpty {
                if label.count <= 24, value.contains("%") || value.contains("→") {
                    return .metric(label: label, value: value)
                }
                return .bullet(title: label, body: value)
            }
        }

        let (title, detail) = splitTitleAndBody(content)
        if let title, !detail.isEmpty {
            return .bullet(title: title, body: detail)
        }
        return .bullet(title: nil, body: content)
    }

    private static func parseMetric(_ line: String) -> MemoryInsightItem? {
        let stripped = line
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns = [
            #"^(Current|Average|Peak|Trend):\s*(.+)$"#,
            #"^([A-Za-z][A-Za-z ]{1,24}):\s*(.+)$"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
                  let labelRange = Range(match.range(at: 1), in: stripped),
                  let valueRange = Range(match.range(at: 2), in: stripped) else {
                continue
            }

            let label = String(stripped[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(stripped[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !value.isEmpty else { continue }
            return .metric(label: label, value: value)
        }

        return nil
    }

    private static func splitTitleAndBody(_ text: String) -> (String?, String) {
        let cleaned = text
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let colonIndex = cleaned.firstIndex(of: ":") {
            let title = String(cleaned[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(cleaned[cleaned.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !body.isEmpty {
                return (title, body)
            }
        }

        if let dashRange = cleaned.range(of: " — ") {
            let title = String(cleaned[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(cleaned[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !body.isEmpty {
                return (title, body)
            }
        }

        if let range = cleaned.range(of: #"\n"#, options: .regularExpression) {
            let title = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !body.isEmpty {
                return (title, body)
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"^(.{4,48}?)([A-Z][a-z].+)$"#),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           let titleRange = Range(match.range(at: 1), in: cleaned),
           let bodyRange = Range(match.range(at: 2), in: cleaned) {
            let title = String(cleaned[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(cleaned[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if title.count >= 4, body.count >= 8 {
                return (title, body)
            }
        }

        return (nil, cleaned)
    }
}
