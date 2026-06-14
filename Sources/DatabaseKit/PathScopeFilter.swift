import Foundation

public struct PathScopeFilter: Sendable, Equatable {
    public let includePathPrefixes: [String]
    public let excludePathPrefixes: [String]

    public init(includePathPrefixes: [String], excludePathPrefixes: [String]) {
        self.includePathPrefixes = includePathPrefixes.map(Self.normalizePrefix)
        self.excludePathPrefixes = excludePathPrefixes.map(Self.normalizePrefix)
    }

    public var isEmpty: Bool {
        includePathPrefixes.isEmpty && excludePathPrefixes.isEmpty
    }

    public func matches(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path

        if !includePathPrefixes.isEmpty {
            let included = includePathPrefixes.contains { prefix in
                normalized == prefixTrimmed(prefix) || normalized.hasPrefix(prefix)
            }
            if !included { return false }
        }

        for prefix in excludePathPrefixes {
            if normalized == prefixTrimmed(prefix) || normalized.hasPrefix(prefix) {
                return false
            }
        }

        return true
    }

    public func sqlPathFilter(column: String = "path") -> (sql: String, arguments: [String]) {
        var clauses: [String] = []
        var arguments: [String] = []

        if !includePathPrefixes.isEmpty {
            let includeClauses = includePathPrefixes.map { _ in
                "(\(column) = ? OR \(column) LIKE ? ESCAPE '\\')"
            }
            clauses.append("(\(includeClauses.joined(separator: " OR ")))")
            for prefix in includePathPrefixes {
                arguments.append(prefixTrimmed(prefix))
                arguments.append(likePattern(for: prefix))
            }
        }

        for prefix in excludePathPrefixes {
            clauses.append("NOT (\(column) = ? OR \(column) LIKE ? ESCAPE '\\')")
            arguments.append(prefixTrimmed(prefix))
            arguments.append(likePattern(for: prefix))
        }

        guard !clauses.isEmpty else { return ("", []) }
        return (clauses.joined(separator: " AND "), arguments)
    }

    private static func normalizePrefix(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardized == "/" { return standardized }
        return standardized.hasSuffix("/") ? standardized : standardized + "/"
    }

    private func prefixTrimmed(_ prefix: String) -> String {
        prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
    }

    private func likePattern(for prefix: String) -> String {
        prefix
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
    }
}
