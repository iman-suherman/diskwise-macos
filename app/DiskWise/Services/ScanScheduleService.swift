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
        let weekday = calendar.component(.weekday, from: now)

        for (mountPath, config) in VolumeScanScheduleStore.shared.allScheduledVolumes() {
            guard let volume = viewModel.mountedVolumes.first(where: { $0.mountPath == mountPath }) else { continue }
            guard !viewModel.isVolumeBusy(volume) else { continue }

            if config.fastScanEnabled,
               config.fastScanWeekdays.contains(weekday),
               hour == config.fastScanHour,
               !hasRecentRun(mountPath: mountPath, mode: .fast, now: now) {
                markRun(mountPath: mountPath, mode: .fast, now: now)
                viewModel.scan(volume: volume, mode: .fast)
                return
            }

            if config.deepScanEnabled,
               config.deepScanWeekdays.contains(weekday),
               hour == config.deepScanHour,
               !hasRecentRun(mountPath: mountPath, mode: .deep, now: now) {
                markRun(mountPath: mountPath, mode: .deep, now: now)
                viewModel.scan(volume: volume, mode: .deep)
                return
            }
        }
    }

    private func hasRecentRun(mountPath: String, mode: ScanMode, now: Date) -> Bool {
        let calendar = Calendar.current
        guard let lastRun = lastRunDate(mountPath: mountPath, mode: mode) else { return false }

        switch mode {
        case .fast:
            return calendar.isDate(lastRun, inSameDayAs: now)
        case .deep:
            let week = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: now)
            let lastWeek = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: lastRun)
            return week.weekOfYear == lastWeek.weekOfYear && week.yearForWeekOfYear == lastWeek.yearForWeekOfYear
        }
    }

    private func lastRunDate(mountPath: String, mode: ScanMode) -> Date? {
        let key = "\(lastRunKeyPrefix).\(mountPath).\(mode.rawValue)"
        let interval = UserDefaults.standard.double(forKey: key)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    private func markRun(mountPath: String, mode: ScanMode, now: Date) {
        let key = "\(lastRunKeyPrefix).\(mountPath).\(mode.rawValue)"
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
    }
}
