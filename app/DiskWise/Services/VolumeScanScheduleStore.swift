import DiskScannerKit
import Foundation

@MainActor
final class VolumeScanScheduleStore: ObservableObject {
    static let shared = VolumeScanScheduleStore()

    private let storageKey = "diskwise.settings.volumeScanSchedules.v1"
    private var schedules: [String: VolumeScanScheduleConfig] = [:]

    private init() {
        load()
    }

    func schedule(forMountPath mountPath: String) -> VolumeScanScheduleConfig {
        schedules[mountPath] ?? ScanScheduleAdvisor.recommendedSchedule()
    }

    func save(_ config: VolumeScanScheduleConfig, forMountPath mountPath: String) {
        schedules[mountPath] = config
        persist()
    }

    func allScheduledVolumes() -> [(mountPath: String, config: VolumeScanScheduleConfig)] {
        schedules
            .filter { $0.value.hasEnabledEntries }
            .map { ($0.key, $0.value) }
            .sorted { $0.mountPath < $1.mountPath }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: VolumeScanScheduleConfig].self, from: data) else {
            schedules = [:]
            return
        }
        schedules = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
