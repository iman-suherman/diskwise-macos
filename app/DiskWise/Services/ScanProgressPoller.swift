import DiskScannerKit
import Foundation

@MainActor
final class ScanProgressPoller: ObservableObject {
    static let shared = ScanProgressPoller()

    private var pollTask: Task<Void, Never>?
    private weak var viewModel: AppViewModel?

    private init() {}

    func startPolling(viewModel: AppViewModel) {
        self.viewModel = viewModel
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self, weak viewModel] in
            while !Task.isCancelled {
                guard let self, let viewModel else { return }
                self.pollOnce(viewModel: viewModel)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        viewModel = nil
    }

    private func pollOnce(viewModel: AppViewModel) {
        guard viewModel.isScanning else { return }

        if let progress = ScanProgressSnapshot.shared.currentProgress() {
            viewModel.applyPolledScanProgress(progress)
        }

        if let logURL = ScanLogMonitor.shared.logFileURL,
           let tailLine = ScanLogTailReader.lastStatusLine(from: logURL) {
            viewModel.applyPolledLogStatus(tailLine)
        }
    }
}
