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

    /// force = true только при явной смене времени пользователем; фоновые вызовы
    /// (открытие приложения, тап по уведомлению) не должны сносить будущее напоминание:
    /// иначе джиттер в окне [T−15;T) переносил бы сегодняшнее напоминание на завтра.
    func scheduleDaily(force: Bool = false) {
        if !force {
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                if let pending = requests.first(where: { $0.identifier == Self.dailyID }),
                   let trigger = pending.trigger as? UNCalendarNotificationTrigger,
                   let next = trigger.nextTriggerDate(), next > Date() {
                    return // будущее напоминание уже висит — не трогаем
                }
                DispatchQueue.main.async { self.scheduleDailyInternal() }
            }
            return
        }
        scheduleDailyInternal()
    }

    private func scheduleDailyInternal() {
        let settings = AppStore.shared.settings
        let content = UNMutableNotificationContent()
        content.title = "Уголёк"
        content.body = "Пора продлить огоньки — тапни, и я напишу твоим друзьям 🔥"
        content.sound = .default

        // дрожание ±15 мин: вместо повторяющегося триггера планируем
        // на конкретный день со случайным смещением и перепланируем после срабатывания
        let jitterMinutes = Int.random(in: -15...15)
        let base = Calendar.current.date(
            bySettingHour: settings.dailyHour,
            minute: settings.dailyMinute,
            second: 0,
            of: .now
        ) ?? .now
        let scheduled = Calendar.current.date(byAdding: .minute, value: jitterMinutes, to: base) ?? base

        // если время уже прошло сегодня — планируем на завтра
        let triggerDate: Date
        if scheduled <= .now {
            triggerDate = Calendar.current.date(byAdding: .day, value: 1, to: scheduled) ?? scheduled
        } else {
            triggerDate = scheduled
        }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
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
            return
        }
        let madeProgress = record.sentCount > 0 || record.failedCount > 0
        if madeProgress {
            scheduleSnoozes()
        } else if !record.results.isEmpty {
            // прогон был, но все чаты оказались недостижимы — часовые снузы тут бессмысленны
            clearSnoozes()
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
            // перепланируем ежедневное напоминание на следующий день с новым дрожанием
            if isDaily {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.scheduleDaily()
                }
            }
        }
    }
}
