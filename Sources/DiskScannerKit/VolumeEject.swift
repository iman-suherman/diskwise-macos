import AppKit
import Foundation

public enum VolumeEject {
    public enum Error: LocalizedError {
        case notEjectable(volumeName: String)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .notEjectable(let volumeName):
                return "\(volumeName) is the system drive and cannot be ejected."
            case .failed(let message):
                return message
            }
        }
    }

    public static func eject(_ volume: MountedVolume) throws {
        guard VolumeDiscovery.canEject(volume) else {
            throw Error.notEjectable(volumeName: volume.name)
        }

        let url = URL(fileURLWithPath: volume.mountPath, isDirectory: true)
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        } catch {
            throw Error.failed(error.localizedDescription)
        }
    }
}
