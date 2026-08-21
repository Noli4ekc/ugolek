import SwiftUI

struct MainTabView: View {
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
    }
}

#Preview {
    MainTabView()
}
