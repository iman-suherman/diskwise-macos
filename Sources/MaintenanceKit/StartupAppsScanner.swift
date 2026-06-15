import Foundation

public final class StartupAppsScanner: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: String
    private let sfltoolPath: String
    private let defaultsPath: String
    private let osascriptPath: String

    public init(
        fileManager: FileManager = .default,
        homeDirectory: String? = nil,
        sfltoolPath: String = "/usr/bin/sfltool",
        defaultsPath: String = "/usr/bin/defaults",
        osascriptPath: String = "/usr/bin/osascript"
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser.path
        self.sfltoolPath = sfltoolPath
        self.defaultsPath = defaultsPath
        self.osascriptPath = osascriptPath
    }

    public func scan() -> StartupAppsScanResult {
        let loginItems = scanLoginItems()
        let dockApps = scanDockApps()
        let launchAgents = scanLaunchAgents()
        let backgroundItems = scanBackgroundItems()

        let dockPaths = Set(dockApps.compactMap(\.path))
        let loginNames = Set(loginItems.map { normalizedName($0.name) })

        var merged: [StartupAppItem] = []

        for item in loginItems {
            let path = item.path
            merged.append(
                StartupAppItem(
                    name: item.name,
                    path: path,
                    bundleIdentifier: item.bundleIdentifier,
                    source: .loginItem,
                    isHidden: item.isHidden,
                    detail: item.detail,
                    alsoInDock: path.map { dockPaths.contains($0) } ?? false,
                    alsoLoginItem: true
                )
            )
        }

        for item in dockApps {
            let isLogin = loginNames.contains(normalizedName(item.name))
                || (item.path.flatMap { path in loginItems.contains { $0.path == path } } ?? false)
            guard !isLogin else { continue }
            merged.append(
                StartupAppItem(
                    name: item.name,
                    path: item.path,
                    bundleIdentifier: item.bundleIdentifier,
                    source: .dockPinned,
                    detail: "Pinned in the Dock",
                    alsoInDock: true,
                    alsoLoginItem: false
                )
            )
        }

        merged.append(contentsOf: launchAgents)
        merged.append(contentsOf: backgroundItems.filter { background in
            !merged.contains(where: { $0.name.caseInsensitiveCompare(background.name) == .orderedSame && $0.source == background.source })
        })

        let sorted = merged.sorted { lhs, rhs in
            if lhs.source.sortOrder != rhs.source.sortOrder {
                return lhs.source.sortOrder < rhs.source.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return StartupAppsScanResult(items: sorted)
    }

    private struct RawItem {
        let name: String
        let path: String?
        let bundleIdentifier: String?
        let isHidden: Bool
        let detail: String
    }

    private func scanLoginItems() -> [RawItem] {
        let script = """
        tell application "System Events"
            set output to ""
            repeat with li in login items
                set itemName to name of li
                set itemPath to ""
                try
                    set itemPath to path of li
                end try
                set itemHidden to hidden of li
                set output to output & itemName & "\\t" & itemPath & "\\t" & itemHidden & linefeed
            end repeat
            return output
        end tell
        """

        guard let output = runCommand(path: osascriptPath, arguments: ["-e", script]) else {
            return []
        }

        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard let name = parts.first, !name.isEmpty else { return nil }
                let path = parts.count > 1 ? sanitizedPath(parts[1]) : nil
                let hidden = parts.count > 2 ? (parts[2].lowercased() == "true") : false
                return RawItem(
                    name: name,
                    path: path,
                    bundleIdentifier: bundleIdentifier(for: path),
                    isHidden: hidden,
                    detail: hidden ? "Hidden login item" : "Registered in Login Items"
                )
            }
    }

    private func scanDockApps() -> [RawItem] {
        guard let output = runCommand(path: defaultsPath, arguments: ["read", "com.apple.dock", "persistent-apps"]) else {
            return []
        }

        let urls = extractDockURLs(from: output)
        return urls.compactMap { urlString in
            guard let url = URL(string: urlString), url.isFileURL else { return nil }
            let path = url.path
            let name = fileManager.displayName(atPath: path)
            return RawItem(
                name: name.replacingOccurrences(of: ".app", with: ""),
                path: path,
                bundleIdentifier: bundleIdentifier(for: path),
                isHidden: false,
                detail: "Pinned in Dock"
            )
        }
    }

    private func scanLaunchAgents() -> [StartupAppItem] {
        let folder = (homeDirectory as NSString).appendingPathComponent("Library/LaunchAgents")
        guard let files = try? fileManager.contentsOfDirectory(atPath: folder) else { return [] }

        return files
            .filter { $0.hasSuffix(".plist") }
            .compactMap { fileName -> StartupAppItem? in
                let path = (folder as NSString).appendingPathComponent(fileName)
                guard let data = fileManager.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { return nil }

                let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
                let keepAlive = plist["KeepAlive"] as? Bool ?? false
                guard runAtLoad || keepAlive else { return nil }

                let label = plist["Label"] as? String ?? fileName.replacingOccurrences(of: ".plist", with: "")
                let programPath = launchAgentProgramPath(from: plist)
                let displayName = launchAgentDisplayName(label: label, programPath: programPath)

                return StartupAppItem(
                    name: displayName,
                    path: programPath,
                    bundleIdentifier: label,
                    source: .launchAgent,
                    detail: keepAlive ? "Launch Agent (KeepAlive)" : "Launch Agent (RunAtLoad)",
                    alsoInDock: false,
                    alsoLoginItem: false
                )
            }
    }

    private func scanBackgroundItems() -> [StartupAppItem] {
        guard let output = runCommand(path: sfltoolPath, arguments: ["dumpbtm"]) else { return [] }
        return parseBackgroundItems(from: output)
    }

    private func parseBackgroundItems(from output: String) -> [StartupAppItem] {
        var items: [StartupAppItem] = []
        var currentName: String?
        var currentType: String?
        var currentDisposition: String?
        var currentURL: String?
        var currentBundleID: String?
        var currentExecutable: String?

        func flush() {
            guard let name = currentName, !name.isEmpty else {
                resetCurrent()
                return
            }

            let disposition = currentDisposition ?? ""
            let isEnabled = disposition.contains("enabled")
            let type = currentType ?? ""

            let isStartupType = type.contains("legacy agent")
                || (type.contains("app") && !type.contains("spotlight") && !type.contains("quicklook"))
            guard isStartupType, isEnabled else {
                resetCurrent()
                return
            }

            if type.contains("spotlight") || type.contains("quicklook") || type.contains("dock tile") {
                resetCurrent()
                return
            }

            let path = sanitizedPath(currentURL ?? currentExecutable)
            items.append(
                StartupAppItem(
                    name: name.replacingOccurrences(of: ".app", with: ""),
                    path: path,
                    bundleIdentifier: currentBundleID,
                    source: .backgroundItem,
                    detail: "Background startup item (\(typeLabel(type)))",
                    alsoInDock: false,
                    alsoLoginItem: false
                )
            )
            resetCurrent()
        }

        func resetCurrent() {
            currentName = nil
            currentType = nil
            currentDisposition = nil
            currentURL = nil
            currentBundleID = nil
            currentExecutable = nil
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") && trimmed.contains(":") {
                flush()
                continue
            }
            if trimmed.hasPrefix("Name:") {
                currentName = trimmed.replacingOccurrences(of: "Name:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Type:") {
                currentType = trimmed.replacingOccurrences(of: "Type:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Disposition:") {
                currentDisposition = trimmed.replacingOccurrences(of: "Disposition:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("URL:") {
                currentURL = trimmed.replacingOccurrences(of: "URL:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Bundle Identifier:") {
                currentBundleID = trimmed.replacingOccurrences(of: "Bundle Identifier:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Executable Path:") {
                currentExecutable = trimmed.replacingOccurrences(of: "Executable Path:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        flush()

        var seen = Set<String>()
        return items.filter { item in
            let key = item.id
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func extractDockURLs(from output: String) -> [String] {
        var urls: [String] = []
        let pattern = #""_CFURLString"\s*=\s*"([^"]+)";"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return urls }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        regex.enumerateMatches(in: output, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let urlRange = Range(match.range(at: 1), in: output) else { return }
            urls.append(String(output[urlRange]))
        }
        return urls
    }

    private func launchAgentProgramPath(from plist: [String: Any]) -> String? {
        if let args = plist["ProgramArguments"] as? [String], let first = args.first {
            return first
        }
        if let program = plist["Program"] as? String {
            return program
        }
        return nil
    }

    private func launchAgentDisplayName(label: String, programPath: String?) -> String {
        if let programPath, programPath.hasSuffix(".app/Contents/MacOS/") || programPath.contains(".app/") {
            let components = programPath.split(separator: "/")
            if let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) {
                return String(components[appIndex]).replacingOccurrences(of: ".app", with: "")
            }
        }

        if label.hasPrefix("homebrew.mxcl.") {
            return label.replacingOccurrences(of: "homebrew.mxcl.", with: "Homebrew: ")
        }

        if let last = label.split(separator: ".").last {
            return String(last)
        }
        return label
    }

    private func bundleIdentifier(for appPath: String?) -> String? {
        guard let appPath, appPath.hasSuffix(".app") else { return nil }
        let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String
        else { return nil }
        return bundleID
    }

    private func sanitizedPath(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "(null)" || trimmed == "missing value" {
            return nil
        }
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return url.path
        }
        return trimmed
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func typeLabel(_ type: String) -> String {
        if type.contains("legacy agent") { return "Launch Agent" }
        if type.contains("legacy daemon") { return "Launch Daemon" }
        if type.contains("app") { return "App" }
        return "Background"
    }

    private func runCommand(path: String, arguments: [String], timeout: TimeInterval = 15) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let group = DispatchGroup()
        group.enter()
        var result: String?
        var terminationStatus: Int32 = -1

        process.terminationHandler = { process in
            terminationStatus = process.terminationStatus
            group.leave()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let completed = group.wait(timeout: .now() + timeout) == .success
        if !completed {
            process.terminate()
            return nil
        }

        guard terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

private extension StartupAppSource {
    var sortOrder: Int {
        switch self {
        case .loginItem: return 0
        case .dockPinned: return 1
        case .launchAgent: return 2
        case .backgroundItem: return 3
        }
    }
}
