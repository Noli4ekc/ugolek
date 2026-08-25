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
    func perform() async throws -> some IntentResult {
        guard SessionStore.shared.isLoggedIn,
              !AppStore.shared.friendsDueToday.isEmpty,
              !RunCoordinator.shared.runActive else {
            return .result()
        }
        LocationKeeper.shared.acquire()
        defer { LocationKeeper.shared.release() }
        let record = await RunCoordinator.shared.startHeadless()
        notifyResult(record)
        return .result()
    }

    private func notifyResult(_ record: RunRecord) {
        let content = UNMutableNotificationContent()
        content.title = "Уголёк"
        if record.sentCount > 0 {
            content.body = "✅ Продлено: \(record.sentCount) · ошибок \(record.failedCount)"
        } else {
            content.body = "Нечего продлевать — все огоньки уже горят 🔥"
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
