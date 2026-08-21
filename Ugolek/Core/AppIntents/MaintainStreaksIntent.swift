import AppIntents

struct MaintainStreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Продлить огоньки"
    static var description = IntentDescription("Написать всем друзьям в TikTok, кому сегодня ещё не отправляли сообщение.")

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        RunCoordinator.shared.start()
        return .result()
    }
}

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
