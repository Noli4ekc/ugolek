import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Главная", systemImage: "flame.fill") }
            FriendsView()
                .tabItem { Label("Друзья", systemImage: "person.2.fill") }
            HistoryView()
                .tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
        .tint(.orange)
        .onAppear {
            ReminderService.shared.requestAndScheduleDaily()
            RunCoordinator.shared.consumePendingAutoRunIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                ReminderService.shared.scheduleDaily()
                RunCoordinator.shared.consumePendingAutoRunIfNeeded()
            }
        }
    }
}

#Preview {
    MainTabView()
}
