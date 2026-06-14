import DiskScannerKit
import Foundation

/// Periodically writes and removes a tiny file on each volume, similar to Amphetamine's drive keep-awake.
enum VolumeKeepAwakePulse {
    static let hiddenFileName = ".diskwise-keepawake"
    static let interval: Duration = .seconds(20)

    static func pulse(mountPath: String, fileManager: FileManager = .default) {
        guard fileManager.fileExists(atPath: mountPath) else { return }
        guard !VolumeDiscovery.isSystemVolume(mountPath: mountPath) else { return }

        let fileURL = URL(fileURLWithPath: mountPath, isDirectory: true)
            .appendingPathComponent(hiddenFileName, isDirectory: false)

        let payload = Data("diskwise-\(Date().timeIntervalSince1970)".utf8)

        do {
            try payload.write(to: fileURL, options: .atomic)
            try fileManager.removeItem(at: fileURL)
        } catch {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
