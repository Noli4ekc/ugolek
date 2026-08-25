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
