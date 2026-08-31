import SwiftUI
import BackgroundTasks

@main
struct UgolekApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ReminderService.shared.activate()
        CatchUpTask.register()
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
