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
}
