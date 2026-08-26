import AppIntents

struct MaintainStreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Продлить огоньки"
    static var description = IntentDescription("Написать всем друзьям в TikTok, кому сегодня ещё не отправляли сообщение.")

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if WIDGET_EXTENSION
        // Расширение не может использовать RunCoordinator (нет WebKit),
        // но кидает сигнал живому процессу через Darwin-уведомление.
        // Приложение, открываясь через openAppWhenRun, ловит его и запускает прогон.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName("ugolek.run.requested" as CFString),
            nil, nil, true
        )
        #else
        RunCoordinator.shared.start()
        #endif
        return .result()
    }
}

#if !WIDGET_EXTENSION
struct UgolekShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MaintainStreaksIntent(),
            phrases: ["Продлить огоньки в \(.applicationName)"],
            shortTitle: "Продлить огоньки",
            systemImageName: "flame.fill"
        )
    }
}
#endif
