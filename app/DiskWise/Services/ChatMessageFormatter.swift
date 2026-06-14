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
        "Top consumers",
        "Optimization tips",
        "Suggested actions",
        "Better computing habits",
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

    static func memoryInsightBlocks(_ text: String) -> [String] {
        formatMemoryInsightForDisplay(text)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
