import Foundation

final class DailyReportScheduler: @unchecked Sendable {
    static let shared = DailyReportScheduler()

    private var checkTask: Task<Void, Never>?
    private var onReportReady: (() -> Void)?

    @MainActor
    func start(onReportReady callback: @escaping @Sendable () -> Void) {
        self.onReportReady = callback

        // If today's report doesn't exist yet and we're past the scheduled time,
        // generate it after a short delay so startup isn't blocked.
        if !DailyReportGenerator.todayReportExists() && isPastScheduledTime() {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                let enabled = CoveSettings.shared.dailyReportEnabled
                if enabled && !DailyReportGenerator.todayReportExists() {
                    _ = await DailyReportGenerator.generate()
                    await MainActor.run { self?.onReportReady?() }
                }
            }
        }

        guard checkTask == nil else { return }

        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                await self?.checkAndGenerate()
            }
        }
    }

    func stop() {
        checkTask?.cancel()
        checkTask = nil
    }

    private func checkAndGenerate() async {
        let enabled = await MainActor.run { CoveSettings.shared.dailyReportEnabled }
        guard enabled else { return }
        guard !DailyReportGenerator.todayReportExists() else { return }
        guard await isScheduledTime() else { return }

        _ = await DailyReportGenerator.generate()
        await MainActor.run { onReportReady?() }
    }

    @MainActor
    private func isScheduledTime() -> Bool {
        let targetTotal = CoveSettings.shared.dailyReportTime  // minutes since midnight
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let nowHour = now.hour, let nowMin = now.minute else { return false }
        let nowTotal = nowHour * 60 + nowMin
        return nowTotal >= targetTotal && nowTotal < targetTotal + 2
    }

    @MainActor
    private func isPastScheduledTime() -> Bool {
        let targetTotal = CoveSettings.shared.dailyReportTime
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let nowHour = now.hour, let nowMin = now.minute else { return false }
        let nowTotal = nowHour * 60 + nowMin
        return nowTotal >= targetTotal + 2
    }
}
