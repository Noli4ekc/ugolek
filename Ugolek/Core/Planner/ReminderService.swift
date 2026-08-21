import UserNotifications

final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderService()

    static let dailyID = "ugolek.daily"
    static let catchupID = "ugolek.catchup"
    static let snoozePrefix = "ugolek.snooze."

    private override init() { super.init() }

    func activate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAndScheduleDaily() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                if settings.authorizationStatus == .notDetermined {
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        if granted { DispatchQueue.main.async { self.scheduleDaily() } }
                    }
                }
                return
            }
            DispatchQueue.main.async { self.scheduleDaily() }
        }
    }

    func scheduleDaily() {
        let settings = AppStore.shared.settings
        let content = UNMutableNotificationContent()
        content.title = "Уголёк"
        content.body = "Пора продлить огоньки — тапни, и я напишу твоим друзьям 🔥"
        content.sound = .default

        var comps = DateComponents()
        comps.hour = settings.dailyHour
        comps.minute = settings.dailyMinute

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: Self.dailyID, content: content, trigger: trigger)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyID])
        center.add(request)
    }

    func scheduleSnoozes(count: Int = 3, intervalMinutes: Int = 60) {
        clearSnoozes()
        let center = UNUserNotificationCenter.current()
        for index in 1...count {
            let content = UNMutableNotificationContent()
            content.title = "Уголёк"
            content.body = "Огоньки ещё не продлены (\(AppStore.shared.friendsDueToday.count) друзей ждут). Тапни!"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(intervalMinutes * 60 * index),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: Self.snoozePrefix + String(index),
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    func clearSnoozes() {
        let ids = (1...5).map { Self.snoozePrefix + String($0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func refreshAfterRun(_ record: RunRecord) {
        let dueLeft = AppStore.shared.friendsDueToday
        if dueLeft.isEmpty {
            clearSnoozes()
        } else if record.sentCount > 0 || record.failedCount > 0 {
            scheduleSnoozes()
        }
    }

    func fireCatchUp() {
        let content = UNMutableNotificationContent()
        content.title = "Уголёк"
        content.body = "Сегодня ещё не продлевал огоньки — \(AppStore.shared.friendsDueToday.count) друзей ждут. Тапни!"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: Self.catchupID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        let isDaily = id == Self.dailyID || id == Self.catchupID
        let isSnooze = id.hasPrefix(Self.snoozePrefix)
        if isDaily || isSnooze {
            await MainActor.run {
                RunCoordinator.shared.pendingAutoRun = true
            }
        }
    }
}
