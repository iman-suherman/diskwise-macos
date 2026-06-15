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
        let btmResult = scanBackgroundTaskManager()
        let appleScriptResult = scanLoginItemsViaAppleScript()
        let dockApps = scanDockApps()
        let launchAgents = scanLaunchAgents()

        let dockPaths = Set(dockApps.compactMap(\.path))
        let btmLoginItems = btmResult.loginItems
        let loginNames = Set(
            (btmLoginItems + appleScriptResult.items).map { normalizedName($0.name) }
        )

        var merged: [StartupAppItem] = []
        var seenLoginKeys = Set<String>()

        for item in btmLoginItems {
            let path = item.path
            let key = loginKey(name: item.name, path: path, bundleID: item.bundleIdentifier)
            guard seenLoginKeys.insert(key).inserted else { continue }
            merged.append(
                StartupAppItem(
                    name: item.name,
                    path: path,
                    bundleIdentifier: item.bundleIdentifier,
                    source: .loginItem,
                    isHidden: item.isHidden,
                    isEnabled: item.isEnabled,
                    detail: item.detail,
                    alsoInDock: path.map { dockPaths.contains($0) } ?? false,
                    alsoLoginItem: true
                )
            )
        }

        for item in appleScriptResult.items {
            let path = item.path
            let key = loginKey(name: item.name, path: path, bundleID: item.bundleIdentifier)
            guard seenLoginKeys.insert(key).inserted else { continue }
            merged.append(
                StartupAppItem(
                    name: item.name,
                    path: path,
                    bundleIdentifier: item.bundleIdentifier,
                    source: .loginItem,
                    isHidden: item.isHidden,
                    isEnabled: item.isEnabled,
                    detail: item.detail,
                    alsoInDock: path.map { dockPaths.contains($0) } ?? false,
                    alsoLoginItem: true
                )
            )
        }

        for item in dockApps {
            let isLogin = loginNames.contains(normalizedName(item.name))
                || (item.path.flatMap { path in merged.contains { $0.path == path && $0.source == .loginItem } } ?? false)
            guard !isLogin else { continue }
            merged.append(
                StartupAppItem(
                    name: item.name,
                    path: item.path,
                    bundleIdentifier: item.bundleIdentifier,
                    source: .dockPinned,
                    detail: "Pinned in Dock",
                    alsoInDock: true,
                    alsoLoginItem: false
                )
            )
        }

        merged.append(contentsOf: launchAgents)

        for item in btmResult.backgroundApps {
            guard !merged.contains(where: {
                $0.source == item.source
                    && $0.name.caseInsensitiveCompare(item.name) == .orderedSame
                    && ($0.bundleIdentifier == item.bundleIdentifier || $0.path == item.path)
            }) else { continue }
            merged.append(item)
        }

        for item in btmResult.legacyAgents {
            guard !merged.contains(where: {
                $0.name.caseInsensitiveCompare(item.name) == .orderedSame
                    && ($0.source == .launchAgent || $0.source == .backgroundItem)
            }) else { continue }
            merged.append(item)
        }

        let sorted = merged.sorted { lhs, rhs in
            if lhs.source.sortOrder != rhs.source.sortOrder {
                return lhs.source.sortOrder < rhs.source.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let diagnostics = StartupAppsScanDiagnostics(
            backgroundTaskManagerAccessible: btmResult.accessible,
            automationPermissionGranted: appleScriptResult.accessGranted,
            needsAdminPassword: btmResult.needsAdminPassword
        )

        return StartupAppsScanResult(items: sorted, diagnostics: diagnostics)
    }

    internal struct RawItem {
        let name: String
        let path: String?
        let bundleIdentifier: String?
        let isHidden: Bool
        let isEnabled: Bool?
        let detail: String
    }

    private struct BTMScanResult {
        let accessible: Bool
        let needsAdminPassword: Bool
        let loginItems: [RawItem]
        let backgroundApps: [StartupAppItem]
        let legacyAgents: [StartupAppItem]
    }

    private struct BTMRecord {
        var name: String?
        var type: String?
        var disposition: String?
        var identifier: String?
        var url: String?
        var bundleIdentifier: String?
        var executablePath: String?
        var parentIdentifier: String?
    }

    private func scanBackgroundTaskManager() -> BTMScanResult {
        let commandResult = runCommandWithStatus(path: sfltoolPath, arguments: ["dumpbtm"])
        guard let output = commandResult.output, !output.isEmpty else {
            let needsAdmin = commandResult.terminationStatus != 0
            return BTMScanResult(
                accessible: false,
                needsAdminPassword: needsAdmin,
                loginItems: [],
                backgroundApps: [],
                legacyAgents: []
            )
        }

        let parsed = parseBackgroundTaskManagerDump(output)
        return BTMScanResult(
            accessible: true,
            needsAdminPassword: false,
            loginItems: parsed.loginItems,
            backgroundApps: parsed.backgroundApps,
            legacyAgents: parsed.legacyAgents
        )
    }

    private func parseBackgroundTaskManagerDump(_ output: String) -> (
        loginItems: [RawItem],
        backgroundApps: [StartupAppItem],
        legacyAgents: [StartupAppItem]
    ) {
        let records = parseBTMRecords(from: output)
        let parentNames = parentAppNames(from: records)

        var loginItems: [RawItem] = []
        var backgroundApps: [StartupAppItem] = []
        var legacyAgents: [StartupAppItem] = []

        for record in records {
            let type = record.type ?? ""
            let disposition = record.disposition ?? ""
            let isEnabled = disposition.contains("enabled")
            let path = sanitizedPath(record.url ?? record.executablePath)
            let bundleID = record.bundleIdentifier

            if type.contains("login item") {
                let displayName = loginItemDisplayName(record: record, parentNames: parentNames)
                loginItems.append(
                    RawItem(
                        name: displayName,
                        path: path,
                        bundleIdentifier: bundleID,
                        isHidden: false,
                        isEnabled: isEnabled,
                        detail: isEnabled ? "Open at Login" : "Open at Login (disabled)"
                    )
                )
                continue
            }

            if type.contains("app") {
                guard !isImporterOrExtension(record) else { continue }
                let displayName = appDisplayName(record: record)
                backgroundApps.append(
                    StartupAppItem(
                        name: displayName,
                        path: path,
                        bundleIdentifier: bundleID,
                        source: .backgroundItem,
                        isEnabled: isEnabled,
                        detail: isEnabled
                            ? "App Background Activity (allowed to run in background)"
                            : "App Background Activity (disabled)",
                        alsoInDock: false,
                        alsoLoginItem: false
                    )
                )
                continue
            }

            if type.contains("legacy agent") || type.contains("legacy daemon") {
                let displayName = record.name ?? bundleID ?? "Background Service"
                legacyAgents.append(
                    StartupAppItem(
                        name: displayName.replacingOccurrences(of: ".app", with: ""),
                        path: path,
                        bundleIdentifier: bundleID,
                        source: .backgroundItem,
                        isEnabled: isEnabled,
                        detail: "Background service (\(typeLabel(type)))",
                        alsoInDock: false,
                        alsoLoginItem: false
                    )
                )
            }
        }

        return (deduplicatedLoginItems(loginItems), deduplicatedBackgroundApps(backgroundApps), legacyAgents)
    }

    private func parseBTMRecords(from output: String) -> [BTMRecord] {
        var records: [BTMRecord] = []
        var current = BTMRecord()

        func flush() {
            if current.type != nil || current.name != nil || current.bundleIdentifier != nil {
                records.append(current)
            }
            current = BTMRecord()
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") && trimmed.contains(":") {
                flush()
                continue
            }
            if trimmed.hasPrefix("Name:") {
                current.name = trimmed.replacingOccurrences(of: "Name:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Type:") {
                current.type = trimmed.replacingOccurrences(of: "Type:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Disposition:") {
                current.disposition = trimmed.replacingOccurrences(of: "Disposition:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Identifier:") {
                current.identifier = trimmed.replacingOccurrences(of: "Identifier:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("URL:") {
                current.url = trimmed.replacingOccurrences(of: "URL:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Bundle Identifier:") {
                current.bundleIdentifier = trimmed.replacingOccurrences(of: "Bundle Identifier:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Executable Path:") {
                current.executablePath = trimmed.replacingOccurrences(of: "Executable Path:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Parent Identifier:") {
                current.parentIdentifier = trimmed.replacingOccurrences(of: "Parent Identifier:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        flush()
        return records
    }

    private func parentAppNames(from records: [BTMRecord]) -> [String: String] {
        var names: [String: String] = [:]
        for record in records {
            guard let identifier = record.identifier,
                  let name = record.name,
                  !name.isEmpty,
                  name != "(null)",
                  record.type?.contains("app") == true
            else { continue }
            names[identifier] = name.replacingOccurrences(of: ".app", with: "")
        }
        return names
    }

    private func loginItemDisplayName(record: BTMRecord, parentNames: [String: String]) -> String {
        if let parentID = record.parentIdentifier, let parentName = parentNames[parentID] {
            return parentName
        }
        if let name = record.name, !name.isEmpty, name != "(null)" {
            return name.replacingOccurrences(of: ".app", with: "")
        }
        if let path = sanitizedPath(record.url ?? record.executablePath) {
            return fileManager.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        }
        if let bundleID = record.bundleIdentifier {
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }
        return "Login Item"
    }

    private func appDisplayName(record: BTMRecord) -> String {
        if let name = record.name, !name.isEmpty, name != "(null)" {
            return name.replacingOccurrences(of: ".app", with: "")
        }
        if let path = sanitizedPath(record.url) {
            return fileManager.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
        }
        if let bundleID = record.bundleIdentifier {
            return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }
        return "Background App"
    }

    private func isImporterOrExtension(_ record: BTMRecord) -> Bool {
        let name = (record.name ?? "").lowercased()
        let bundleID = (record.bundleIdentifier ?? "").lowercased()
        return name.contains("spotlight")
            || name.contains("quick look")
            || name.contains(".appex")
            || name.contains(".mdimporter")
            || name.contains("importer")
            || bundleID.contains("quicklook")
            || bundleID.contains("spotlight")
    }

    private func deduplicatedLoginItems(_ items: [RawItem]) -> [RawItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = loginKey(name: item.name, path: item.path, bundleID: item.bundleIdentifier)
            return seen.insert(key).inserted
        }
    }

    private func deduplicatedBackgroundApps(_ items: [StartupAppItem]) -> [StartupAppItem] {
        var seen = Set<String>()
        return items.filter { item in
            let key = "\(item.bundleIdentifier ?? item.name)|\(item.path ?? "")"
            return seen.insert(key).inserted
        }
    }

    private struct AppleScriptLoginResult {
        let items: [RawItem]
        let accessGranted: Bool
    }

    private func scanLoginItemsViaAppleScript() -> AppleScriptLoginResult {
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

        let commandResult = runCommandWithStatus(path: osascriptPath, arguments: ["-e", script])
        guard let output = commandResult.output else {
            return AppleScriptLoginResult(items: [], accessGranted: false)
        }

        let items = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> RawItem? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard let name = parts.first, !name.isEmpty else { return nil }
                let path = parts.count > 1 ? sanitizedPath(parts[1]) : nil
                let hidden = parts.count > 2 ? (parts[2].lowercased() == "true") : false
                return RawItem(
                    name: name,
                    path: path,
                    bundleIdentifier: bundleIdentifier(for: path),
                    isHidden: hidden,
                    isEnabled: true,
                    detail: hidden ? "Hidden login item" : "Registered in Login Items"
                )
            }

        return AppleScriptLoginResult(items: items, accessGranted: commandResult.terminationStatus == 0)
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
                isEnabled: nil,
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

    private func loginKey(name: String, path: String?, bundleID: String?) -> String {
        if let bundleID, !bundleID.isEmpty {
            return "bundle|\(bundleID.lowercased())"
        }
        if let path, !path.isEmpty {
            return "path|\(path.lowercased())"
        }
        return "name|\(normalizedName(name))"
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
        if trimmed.hasPrefix("Contents/") {
            return nil
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

    private struct CommandResult {
        let output: String?
        let terminationStatus: Int32
    }

    private func runCommand(path: String, arguments: [String], timeout: TimeInterval = 15) -> String? {
        runCommandWithStatus(path: path, arguments: arguments, timeout: timeout).output
    }

    private func runCommandWithStatus(path: String, arguments: [String], timeout: TimeInterval = 15) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let group = DispatchGroup()
        group.enter()
        var terminationStatus: Int32 = -1

        process.terminationHandler = { process in
            terminationStatus = process.terminationStatus
            group.leave()
        }

        do {
            try process.run()
        } catch {
            return CommandResult(output: nil, terminationStatus: -1)
        }

        let completed = group.wait(timeout: .now() + timeout) == .success
        if !completed {
            process.terminate()
            return CommandResult(output: nil, terminationStatus: -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandResult(output: output, terminationStatus: terminationStatus)
    }

    #if DEBUG
    internal func parseBackgroundTaskManagerDumpForTesting(_ output: String) -> (
        loginItems: [RawItem],
        backgroundApps: [StartupAppItem],
        legacyAgents: [StartupAppItem]
    ) {
        parseBackgroundTaskManagerDump(output)
    }
    #endif
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
