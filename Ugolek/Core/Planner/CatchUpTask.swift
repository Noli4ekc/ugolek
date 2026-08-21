import BackgroundTasks
import Foundation

enum CatchUpTask {
    static let identifier = "com.ugolek.app.catchup"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task as! BGProcessingTask)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGProcessingTask) {
        schedule()

        Task { @MainActor in
            let store = AppStore.shared
            let settings = store.settings

            var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            comps.hour = settings.dailyHour
            comps.minute = settings.dailyMinute

            guard let dailyAt = Calendar.current.date(from: comps) else {
                task.setTaskCompleted(success: true)
                return
            }

            let overdue = Date() > dailyAt.addingTimeInterval(45 * 60)
            if overdue, SessionStore.shared.isLoggedIn, !store.friendsDueToday.isEmpty {
                ReminderService.shared.fireCatchUp()
            }

            task.setTaskCompleted(success: true)
        }
    }
}
