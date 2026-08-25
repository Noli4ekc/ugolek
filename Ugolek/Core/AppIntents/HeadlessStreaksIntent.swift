import AppIntents
import UserNotifications

// Фоновый прогон без открытия приложения (уровень 2).
// Выбирается в Командах как действие автоматизации «Время суток»:
// система будит процесс в фоне, гео-держатель не даёт ему уснуть до конца рассылки.
struct HeadlessStreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Продлить огоньки (фон)"
    static var description = IntentDescription("Запустить рассылку в фоне, не открывая приложение.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SessionStore.shared.isLoggedIn else {
            return .result(dialog: "Нужен вход в TikTok — открой Уголёк и войди")
        }
        guard !RunCoordinator.shared.runActive else {
            return .result(dialog: "Прогон уже идёт")
        }
        guard !AppStore.shared.friendsDueToday.isEmpty else {
            return .result(dialog: "Все огоньки уже продлены 🔥")
        }
        LocationKeeper.shared.acquire()
        defer { LocationKeeper.shared.release() }
        let record = await RunCoordinator.shared.startHeadless()
        notifyResult(record)
        return .result(dialog: "Отправлено \(record.sentCount) · ошибок \(record.failedCount)")
    }

    private func notifyResult(_ record: RunRecord) {
        let content = UNMutableNotificationContent()
        content.title = "Уголёк"
        switch (record.sentCount, record.skippedCount, record.failedCount) {
        case (0, 0, 0):
            content.body = "Нечего продлевать — все огоньки уже горят 🔥"
        case (_, _, 0):
            content.body = "✅ Продлено: \(record.sentCount)"
                + (record.skippedCount > 0 ? " · пропущено \(record.skippedCount)" : "")
        case (let sent, let skipped, let failed):
            content.body = "Продлено \(sent), ошибок \(failed)"
                + (skipped > 0 ? ", пропущено \(skipped)" : "")
                + ". Подробности — в Истории."
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ugolek.headless.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
