import DiskScannerKit
import Foundation

@MainActor
final class ScanScheduleService {
    static let shared = ScanScheduleService()

    private let lastRunKeyPrefix = "diskwise.schedule.lastRun"
    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluateSchedules()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
        evaluateSchedules()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func evaluateSchedules() {
        guard let viewModel = AppViewModel.current else { return }
        guard !viewModel.isScanning, !viewModel.isAnalyzing, !viewModel.isStartingUp else { return }

        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let weekday = calendar.component(.weekday, from: now)

        var dueJobs: [(mountPath: String, entry: ScanScheduleEntry, volume: MountedVolume)] = []

        for (mountPath, config) in VolumeScanScheduleStore.shared.allScheduledVolumes() {
            guard let volume = viewModel.mountedVolumes.first(where: { $0.mountPath == mountPath }) else { continue }
            guard !viewModel.isVolumeBusy(volume) else { continue }

            for entry in config.entries where entry.isEnabled {
                guard entry.weekdays.contains(weekday) else { continue }
                guard hour == entry.hour, minute >= entry.minute else { continue }
                guard !hasRecentRun(mountPath: mountPath, entry: entry, now: now) else { continue }
                dueJobs.append((mountPath, entry, volume))
            }
        }

        dueJobs.sort { lhs, rhs in
            if lhs.entry.mode != rhs.entry.mode {
                return lhs.entry.mode == .fast
            }
            return lhs.entry.hour < rhs.entry.hour
                || (lhs.entry.hour == rhs.entry.hour && lhs.entry.minute < rhs.entry.minute)
        }

        for job in dueJobs {
            markRun(mountPath: job.mountPath, entry: job.entry, now: now)
            viewModel.enqueueScheduledScan(volume: job.volume, mode: job.entry.mode)
        }
    }

    private func hasRecentRun(mountPath: String, entry: ScanScheduleEntry, now: Date) -> Bool {
        let calendar = Calendar.current
        guard let lastRun = lastRunDate(mountPath: mountPath, entryID: entry.id) else { return false }

        if entry.mode == .deep, entry.weekdays.count <= 2 {
            let week = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
            let lastWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: lastRun)
            return week.weekOfYear == lastWeek.weekOfYear && week.yearForWeekOfYear == lastWeek.yearForWeekOfYear
        }
        return calendar.isDate(lastRun, inSameDayAs: now)
    }

    private func lastRunDate(mountPath: String, entryID: UUID) -> Date? {
        let key = "\(lastRunKeyPrefix).\(mountPath).\(entryID.uuidString)"
        let interval = UserDefaults.standard.double(forKey: key)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func markRun(mountPath: String, entry: ScanScheduleEntry, now: Date) {
        let key = "\(lastRunKeyPrefix).\(mountPath).\(entry.id.uuidString)"
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
    }
}
