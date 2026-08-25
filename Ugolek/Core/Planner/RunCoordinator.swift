import Foundation
import Observation
import UIKit
import UserNotifications

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

    private init() {
        // Разрешение на геолокацию забрали — авто-режим честно выключаем и сообщаем
        NotificationCenter.default.addObserver(
            forName: .geoPermissionRevoked, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                guard AppStore.shared.settings.geoAlwaysAuto else { return }
                AppStore.shared.settings.geoAlwaysAuto = false
                AutoRunner.shared.disarm()
                LocationKeeper.shared.stopPersistent()

                let content = UNMutableNotificationContent()
                content.title = "Уголёк"
                content.body = "Фоновый режим выключен: у Уголька больше нет доступа к геолокации"
                let request = UNNotificationRequest(
                    identifier: "ugolek.geoRevoked",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                )
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    func start(forceAll: Bool = false) {
        guard !runActive else { return }
        runActive = true
        progressText = ""
        progressDone = 0
        progressTotal = 0
        UIApplication.shared.isIdleTimerDisabled = true
        LocationKeeper.shared.acquire()

        Task {
            let record = await StreakEngine.run(forceAll: forceAll) { [weak self] update in
                LocationKeeper.shared.poke()
                self?.progressText = update.text
                self?.progressDone = update.done
                self?.progressTotal = update.total
            }
            UIApplication.shared.isIdleTimerDisabled = false
            LocationKeeper.shared.release()
            runActive = false
            lastSummary = record
            showSummary = !record.results.isEmpty
            ReminderService.shared.refreshAfterRun(record)
        }
    }

    /// Фоновый прогон без UI (уровень 2). Историю пишет сам StreakEngine.
    @discardableResult
    func startHeadless() async -> RunRecord {
        guard !runActive else { return RunRecord(date: .now, durationSeconds: 0, results: []) }
        runActive = true
        progressText = "Фоновое продление…"
        LocationKeeper.shared.acquire()
        defer {
            LocationKeeper.shared.release()
            runActive = false
        }
        let record = await StreakEngine.run { [weak self] update in
            LocationKeeper.shared.poke()
            self?.progressText = update.text
            self?.progressDone = update.done
            self?.progressTotal = update.total
        }
        ReminderService.shared.refreshAfterRun(record)
        return record
    }

    /// Тестовый прогон без отправки (проверка «Гео всегда»). Уважает runActive.
    @discardableResult
    func startDryTest() async -> RunRecord {
        guard !runActive else {
            return RunRecord(date: .now, durationSeconds: 0, results: [
                FriendResult(friendId: UUID(), handle: "—", status: .failed, detail: "Уже идёт другой прогон")
            ])
        }
        runActive = true
        LocationKeeper.shared.acquire()
        defer {
            LocationKeeper.shared.release()
            runActive = false
        }
        return await StreakEngine.run(dryRun: true) { _ in }
    }

    func consumePendingAutoRunIfNeeded() {
        guard pendingAutoRun else { return }
        pendingAutoRun = false
        guard SessionStore.shared.isLoggedIn, !AppStore.shared.friendsDueToday.isEmpty else { return }
        start()
    }
}
