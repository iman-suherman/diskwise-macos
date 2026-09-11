import Foundation

public enum PhotosScreenshotKeepAction: String, Sendable, Codable {
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

public struct PhotosScreenshotInsight: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let keepScore: Int
    public let action: PhotosScreenshotKeepAction
    public let reason: String
    public let sourceApp: String?

    public init(
        id: String,
        label: String,
        keepScore: Int,
        action: PhotosScreenshotKeepAction,
        reason: String,
        sourceApp: String? = nil
    ) {
        self.id = id
        self.label = label
        self.keepScore = max(0, min(100, keepScore))
        self.action = action
        self.reason = reason
        self.sourceApp = sourceApp
    }
}

/// On-device screenshot labels and keep scores for PhotoKit assets.
/// OCR text is optional — metadata-only scores still produce a date label.
public enum PhotosScreenshotInsightEngine {
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
        ("mail", "Mail"),
        ("notes", "Notes"),
        ("calendar", "Calendar"),
        ("maps", "Maps"),
        ("zoom", "Zoom"),
        ("meet", "Video call"),
        ("facetime", "FaceTime"),
        ("settings", "Settings"),
    ]

    public static func insight(
        for asset: PhotoAssetRecord,
        ocrText: String = "",
        now: Date = Date()
    ) -> PhotosScreenshotInsight {
        let filename = asset.originalFilename ?? ""
        let haystack = (ocrText + " " + filename).lowercased()
        let matchedApp = appHints.first { haystack.contains($0.needle) }

        var score = 42
        var reasons: [String] = []

        if asset.isFavorite {
            score += 36
            reasons.append("marked favorite")
        }

        if let age = asset.creationDate {
            let days = now.timeIntervalSince(age) / 86_400
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

        if matchesAny(haystack, ["settings"]) {
            score -= 10
            reasons.append("settings screen")
        }

        if asset.byteSize > 0 && asset.byteSize < 80_000 {
            score -= 6
        }

        let action: PhotosScreenshotKeepAction
        if score < 40 {
            action = .trash
        } else if score < 65 {
            action = .review
        } else {
            action = .keep
        }

        let label = makeLabel(
            filename: filename,
            ocrText: ocrText,
            matchedApp: matchedApp?.label,
            createdAt: asset.creationDate
        )
        let reason = capitalizedReason(reasons, fallback: defaultReason(for: action))

        return PhotosScreenshotInsight(
            id: asset.id,
            label: label,
            keepScore: score,
            action: action,
            reason: reason,
            sourceApp: matchedApp?.label
        )
    }

    public static func ranked(
        _ assets: [PhotoAssetRecord],
        ocrByID: [String: String] = [:],
        now: Date = Date()
    ) -> [PhotosScreenshotInsight] {
        assets
            .map { insight(for: $0, ocrText: ocrByID[$0.id] ?? "", now: now) }
            .sorted { lhs, rhs in
                if lhs.action != rhs.action {
                    return sortRank(lhs.action) < sortRank(rhs.action)
                }
                return lhs.keepScore < rhs.keepScore
            }
    }

    private static func sortRank(_ action: PhotosScreenshotKeepAction) -> Int {
        switch action {
        case .trash: return 0
        case .review: return 1
        case .keep: return 2
        }
    }

    private static func makeLabel(
        filename: String,
        ocrText: String,
        matchedApp: String?,
        createdAt: Date?
    ) -> String {
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

        if let createdAt {
            let formatted = createdAt.formatted(date: .abbreviated, time: .omitted)
            return "Screenshot · \(formatted)"
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

    private static func defaultReason(for action: PhotosScreenshotKeepAction) -> String {
        switch action {
        case .trash: return "Easy to recapture if you still need it"
        case .review: return "Check this one before moving it to Recently Deleted"
        case .keep: return "Looks more useful than a typical screenshot"
        }
    }

    private static func matchesAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
