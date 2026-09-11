import Foundation
import DatabaseKit

public enum ScreenshotKeepAction: String, Sendable, Codable {
    case trash
    case review
    case keep

    public var label: String {
        switch self {
        case .trash: return "Delete recommended"
        case .review: return "Review first"
        case .keep: return "Likely keep"
        }
    }
}

public struct ScreenshotInsight: Sendable, Codable, Identifiable {
    public var id: String { path }
    public let path: String
    public let label: String
    public let keepScore: Int
    public let action: ScreenshotKeepAction
    public let reason: String
    public let sourceApp: String?

    public init(
        path: String,
        label: String,
        keepScore: Int,
        action: ScreenshotKeepAction,
        reason: String,
        sourceApp: String? = nil
    ) {
        self.path = path
        self.label = label
        self.keepScore = max(0, min(100, keepScore))
        self.action = action
        self.reason = reason
        self.sourceApp = sourceApp
    }
}

public enum ScreenshotInsightEngine {
    private static let appHints: [(needle: String, label: String)] = [
        ("whatsapp", "WhatsApp chat"),
        ("telegram", "Telegram chat"),
        ("imessage", "Messages"),
        ("messages", "Messages"),
        ("slack", "Slack"),
        ("discord", "Discord"),
        ("line app", "LINE chat"),
        ("instagram", "Instagram"),
        ("safari", "Safari"),
        ("chrome", "Chrome"),
        ("finder", "Finder window"),
        ("system settings", "System Settings"),
        ("system preferences", "System Settings"),
        ("mail", "Mail"),
        ("notes", "Notes"),
        ("calendar", "Calendar"),
        ("maps", "Maps"),
        ("xcode", "Xcode"),
        ("terminal", "Terminal"),
        ("zoom", "Zoom"),
        ("meet", "Video call"),
        ("facetime", "FaceTime"),
    ]

    public static func insight(for file: FileRecord, ocrText: String = "") -> ScreenshotInsight {
        let filename = URL(fileURLWithPath: file.path).lastPathComponent
        let haystack = (ocrText + " " + filename).lowercased()
        let matchedApp = appHints.first { haystack.contains($0.needle) }

        var score = 42
        var reasons: [String] = []

        if let age = file.lastAccessed ?? file.modifiedAt ?? file.createdAt {
            let days = Date().timeIntervalSince(age) / 86_400
            if days < 7 {
                score += 22
                reasons.append("captured recently")
            } else if days < 30 {
                score += 8
            } else if days > 365 {
                score -= 22
                reasons.append("over a year old")
            } else if days > 90 {
                score -= 12
                reasons.append("several months old")
            }
        }

        if matchesAny(haystack, ["otp", "2fa", "verification code", "one-time", "password", "passcode"]) {
            score -= 32
            reasons.append("looks like a code or password")
        }

        if matchesAny(haystack, ["invoice", "receipt", "boarding pass", "contract", "ticket", "confirmation"]) {
            score += 24
            reasons.append("may be a document you want to keep")
        }

        if matchesAny(haystack, ["whatsapp", "telegram", "imessage", "slack", "discord", "line "]) {
            score -= 16
            reasons.append("chat screenshot")
        }

        if matchesAny(haystack, ["system settings", "system preferences", "settings"]) {
            score -= 10
            reasons.append("settings screen")
        }

        if file.size < 80_000 {
            score -= 6
        }

        let action: ScreenshotKeepAction
        if score < 40 {
            action = .trash
        } else if score < 65 {
            action = .review
        } else {
            action = .keep
        }

        let label = makeLabel(filename: filename, ocrText: ocrText, matchedApp: matchedApp?.label)
        let reason = capitalizedReason(reasons, fallback: defaultReason(for: action))

        return ScreenshotInsight(
            path: file.path,
            label: label,
            keepScore: score,
            action: action,
            reason: reason,
            sourceApp: matchedApp?.label
        )
    }

    public static func rankedForReview(_ files: [FileRecord], ocrByPath: [String: String] = [:]) -> [ScreenshotInsight] {
        files
            .map { insight(for: $0, ocrText: ocrByPath[$0.path] ?? "") }
            .sorted { lhs, rhs in
                if lhs.action != rhs.action {
                    return sortRank(lhs.action) < sortRank(rhs.action)
                }
                return lhs.keepScore < rhs.keepScore
            }
    }

    private static func sortRank(_ action: ScreenshotKeepAction) -> Int {
        switch action {
        case .trash: return 0
        case .review: return 1
        case .keep: return 2
        }
    }

    private static func makeLabel(filename: String, ocrText: String, matchedApp: String?) -> String {
        if let matchedApp {
            return matchedApp
        }

        let snippet = ocrText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.count >= 6 && $0.rangeOfCharacter(from: .letters) != nil }
            ?? ocrText.trimmingCharacters(in: .whitespacesAndNewlines)

        if snippet.count >= 6 {
            let clipped = snippet.count > 42 ? String(snippet.prefix(39)) + "…" : snippet
            return clipped
        }

        if let dateHint = screenshotDateHint(filename: filename) {
            return "Screenshot · \(dateHint)"
        }

        return "Screenshot"
    }

    private static func screenshotDateHint(filename: String) -> String? {
        let pattern = #"(\d{4})[-.](\d{2})[-.](\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              let year = Range(match.range(at: 1), in: filename),
              let month = Range(match.range(at: 2), in: filename),
              let day = Range(match.range(at: 3), in: filename)
        else {
            return nil
        }
        return "\(filename[year])-\(filename[month])-\(filename[day])"
    }

    private static func capitalizedReason(_ parts: [String], fallback: String) -> String {
        guard let first = parts.first else { return fallback }
        let joined = parts.joined(separator: " · ")
        return first.prefix(1).uppercased() + joined.dropFirst()
    }

    private static func defaultReason(for action: ScreenshotKeepAction) -> String {
        switch action {
        case .trash: return "Easy to recapture if you still need it"
        case .review: return "Check this one before moving it to Trash"
        case .keep: return "Looks more useful than a typical screenshot"
        }
    }

    private static func matchesAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
