import SwiftUI
import BackgroundTasks

@main
struct UgolekApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ReminderService.shared.activate()
        CatchUpTask.register()
        // Уровень 3: после перезагрузки/перезапуска оживляем «Гео всегда»
        if AppStore.shared.settings.geoAlwaysAuto {
            LocationKeeper.shared.startPersistent()
            AutoRunner.shared.arm()
        }
        // Кнопка 🔥 в шторке: расширение кидает Darwin-сигнал → запускаем прогон.
        // Если приложение уже в фоне — сработает при пробуждении через openAppWhenRun;
        // если уже на переднем плане — запустится немедленно.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    RunCoordinator.shared.pendingAutoRun = true
                    RunCoordinator.shared.consumePendingAutoRunIfNeeded()
                }
            },
            "ugolek.run.requested" as CFString,
            nil,
            .deliverImmediately
        )
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                CatchUpTask.schedule()
            }
        }
    }
}
