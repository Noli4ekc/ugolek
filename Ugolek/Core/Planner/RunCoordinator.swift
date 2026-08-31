import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class RunCoordinator {
    static let shared = RunCoordinator()

    var runActive = false
    var progressText = ""
    var progressDone = 0
    var progressTotal = 0
    var lastSummary: RunRecord?
    var showSummary = false
    var pendingAutoRun = false

    func start(forceAll: Bool = false) {
        guard !runActive else { return }
        runActive = true
        progressText = ""
        progressDone = 0
        progressTotal = 0
        UIApplication.shared.isIdleTimerDisabled = true

        Task {
            let record = await StreakEngine.run(forceAll: forceAll) { [weak self] update in
                self?.progressText = update.text
                self?.progressDone = update.done
                self?.progressTotal = update.total
            }
            UIApplication.shared.isIdleTimerDisabled = false
            runActive = false
            lastSummary = record
            showSummary = !record.results.isEmpty
            ReminderService.shared.refreshAfterRun(record)
        }
    }

    func consumePendingAutoRunIfNeeded() {
        guard pendingAutoRun else { return }
        pendingAutoRun = false
        guard SessionStore.shared.isLoggedIn, !AppStore.shared.friendsDueToday.isEmpty else { return }
        start()
    }
}
