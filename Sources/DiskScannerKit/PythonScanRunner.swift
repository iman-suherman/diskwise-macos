import Foundation

public enum PythonScanRunnerError: Error, LocalizedError {
    case scriptNotFound
    case pythonNotFound
    case launchFailed(String)
    case scannerFailed(String)
    case cancelled
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "Python scanner script was not found in the app bundle."
        case .pythonNotFound:
            return "Python 3 is required but was not found on this Mac."
        case .launchFailed(let detail):
            return "Could not start the Python scanner: \(detail)"
        case .scannerFailed(let detail):
            return "Python scanner failed: \(detail)"
        case .cancelled:
            return "Scan was cancelled."
        case .invalidOutput(let detail):
            return "Invalid scanner output: \(detail)"
        }
    }
}

public struct PythonScanSession: Sendable {
    public let logFileURL: URL
    public let scriptURL: URL
    public let pythonExecutable: String
}

public final class PythonScanRunner: @unchecked Sendable {
    private let scriptURL: URL
    private let fileManager: FileManager
    private var process: Process?
    private let processLock = NSLock()

    public init(scriptURL: URL, fileManager: FileManager = .default) {
        self.scriptURL = scriptURL
        self.fileManager = fileManager
    }

    public static func bundledScriptURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "diskwise_scan", withExtension: "py", subdirectory: "Scanner")
            ?? bundle.url(forResource: "diskwise_scan", withExtension: "py")
    }

    public static func makeLogFileURL(fileManager: FileManager = .default) throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let logsDirectory = appSupport
            .appendingPathComponent("DiskWise", isDirectory: true)
            .appendingPathComponent("scan-logs", isDirectory: true)
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return logsDirectory.appendingPathComponent("scan-\(timestamp).log")
    }

    public static var isPythonAvailable: Bool {
        resolvePythonExecutable() != nil
    }

    public static func bundledInstallScriptURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "install_python", withExtension: "sh", subdirectory: "Scanner")
            ?? bundle.url(forResource: "install_python", withExtension: "sh")
    }

    public static func resolvePythonExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if validatesPythonVersion(at: path) {
                return path
            }
        }
        return nil
    }

    private static func validatesPythonVersion(at path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func makeSession(logFileURL: URL? = nil) throws -> PythonScanSession {
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw PythonScanRunnerError.scriptNotFound
        }
        guard let pythonExecutable = Self.resolvePythonExecutable() else {
            throw PythonScanRunnerError.pythonNotFound
        }
        let resolvedLogURL = try logFileURL ?? Self.makeLogFileURL(fileManager: fileManager)
        return PythonScanSession(
            logFileURL: resolvedLogURL,
            scriptURL: scriptURL,
            pythonExecutable: pythonExecutable
        )
    }

    public func scan(
        mountPath: URL,
        mode: ScanMode = .fast,
        tieredVolumeScan: Bool = false,
        session: PythonScanSession,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
        onLogLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> [ScannedFile] {
        guard fileManager.fileExists(atPath: mountPath.path) else {
            throw FileScannerError.mountPathUnavailable(mountPath.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: session.pythonExecutable)
        process.arguments = [
            session.scriptURL.path,
            "--root", mountPath.path,
            "--mode", mode.rawValue,
            "--log-file", session.logFileURL.path,
            "--verbose",
        ]
        if tieredVolumeScan {
            process.arguments?.append("--tiered")
        }

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        processLock.lock()
        self.process = process
        processLock.unlock()

        defer {
            processLock.lock()
            self.process = nil
            processLock.unlock()
        }

        do {
            try process.run()
        } catch {
            throw PythonScanRunnerError.launchFailed(error.localizedDescription)
        }

        var scannedFiles: [ScannedFile] = []
        let handle = stdoutPipe.fileHandleForReading
        var lineBuffer = ""

        while process.isRunning || handle.availableData.isEmpty == false {
            if isCancelled?() == true {
                process.terminate()
                throw PythonScanRunnerError.cancelled
            }

            let chunk = handle.availableData
            if chunk.isEmpty {
                if process.isRunning {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                continue
            }

            guard let chunkText = String(data: chunk, encoding: .utf8) else { continue }
            lineBuffer += chunkText

            while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
                let line = String(lineBuffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                lineBuffer.removeSubrange(...newlineIndex)
                guard !line.isEmpty else { continue }

                switch parseLine(line) {
                case .progress(let progress):
                    onProgress?(progress)
                case .file(let scanned):
                    scannedFiles.append(scanned)
                case .log(let message):
                    onLogLine?(message)
                case .done:
                    break
                case .error(let message, let cancelled):
                    if cancelled {
                        throw PythonScanRunnerError.cancelled
                    }
                    throw PythonScanRunnerError.scannerFailed(message)
                case .ignored:
                    break
                }
            }
        }

        process.waitUntilExit()

        if isCancelled?() == true {
            throw PythonScanRunnerError.cancelled
        }

        switch process.terminationStatus {
        case 0:
            return scannedFiles
        case 2:
            throw PythonScanRunnerError.cancelled
        default:
            throw PythonScanRunnerError.scannerFailed("Scanner exited with status \(process.terminationStatus)")
        }
    }

    public func cancelRunningScan() {
        processLock.lock()
        defer { processLock.unlock() }
        process?.terminate()
    }

    private enum ParsedLine {
        case progress(ScanProgress)
        case file(ScannedFile)
        case log(String)
        case done
        case error(message: String, cancelled: Bool)
        case ignored
    }

    private func parseLine(_ line: String) -> ParsedLine {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return .ignored
        }

        switch type {
        case "progress":
            let operationRaw = json["operation"] as? String ?? ScanOperation.enumeratingFiles.rawValue
            let operation = ScanOperation(rawValue: operationRaw) ?? .enumeratingFiles
            return .progress(
                ScanProgress(
                    scannedCount: json["scannedCount"] as? Int ?? 0,
                    currentPath: json["currentPath"] as? String ?? "",
                    bytesIndexed: json["bytesIndexed"] as? Int64 ?? Int64(json["bytesIndexed"] as? Int ?? 0),
                    operation: operation,
                    detail: json["detail"] as? String,
                    directoriesProcessed: json["directoriesProcessed"] as? Int,
                    directoriesTotal: json["directoriesTotal"] as? Int,
                    identifiedDirectories: json["identifiedDirectories"] as? [String],
                    activeDirectories: json["activeDirectories"] as? [String],
                    completedDirectories: json["completedDirectories"] as? [String]
                )
            )
        case "file":
            return .file(
                ScannedFile(
                    path: json["path"] as? String ?? "",
                    size: json["size"] as? Int64 ?? Int64(json["size"] as? Int ?? 0),
                    createdAt: date(from: json["createdAt"]),
                    modifiedAt: date(from: json["modifiedAt"]),
                    lastAccessed: date(from: json["lastAccessed"]),
                    extensionName: json["extensionName"] as? String,
                    isDirectory: json["isDirectory"] as? Bool ?? false
                )
            )
        case "log":
            return .log(json["message"] as? String ?? line)
        case "done":
            return .done
        case "error":
            return .error(
                message: json["message"] as? String ?? "Unknown scanner error",
                cancelled: json["cancelled"] as? Bool ?? false
            )
        default:
            return .ignored
        }
    }

    private func date(from value: Any?) -> Date? {
        switch value {
        case let timestamp as TimeInterval:
            return Date(timeIntervalSince1970: timestamp)
        case let timestamp as Double:
            return Date(timeIntervalSince1970: timestamp)
        case let timestamp as Int:
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        default:
            return nil
        }
    }
}
