import Foundation

// Планировщик авто-режима (уровень 3): пока «Гео всегда» включено и процесс жив,
// стреляет прогоном в время напоминалки ± 15 мин дрожания, затем перезаряжается на завтра.
@MainActor
final class AutoRunner {
    static let shared = AutoRunner()

    private(set) var nextRunDate: Date?
    private var timer: Task<Void, Never>?

    private init() {}

    func arm() {
        scheduleNext()
    }

    func disarm() {
        timer?.cancel()
        timer = nil
        nextRunDate = nil
    }

    /// Пересчёт при смене времени напоминания в настройках.
    func reschedule() {
        guard AppStore.shared.settings.geoAlwaysAuto else { return }
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.cancel()
        timer = nil

        let settings = AppStore.shared.settings
        let jitter = Int.random(in: -15...15)
        let base = Calendar.current.date(
            bySettingHour: settings.dailyHour,
            minute: settings.dailyMinute,
            second: 0,
            of: .now
        ) ?? .now
        var target = Calendar.current.date(byAdding: .minute, value: jitter, to: base) ?? base
        if target <= Date().addingTimeInterval(60) {
            target = Calendar.current.date(byAdding: .day, value: 1, to: target) ?? target
        }
        nextRunDate = target

        timer = Task { [weak self] in
            let wait = Date().distance(to: target)
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
            }
            self?.fireAndReschedule()
        }
    }

    private func fireAndReschedule() {
        // Пропускаем тихо: нет логина / нечего слать / прогон уже идёт — просто завтра
        guard AppStore.shared.settings.geoAlwaysAuto else { disarm(); return }
        guard SessionStore.shared.isLoggedIn else { scheduleNext(); return }
        guard !AppStore.shared.friendsDueToday.isEmpty else { scheduleNext(); return }
        guard !RunCoordinator.shared.runActive else { scheduleNext(); return }
        RunCoordinator.shared.start()
        scheduleNext()
    }
}
