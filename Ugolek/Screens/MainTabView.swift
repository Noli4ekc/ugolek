import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ugolek.onboardingComplete") private var onboardingComplete = false
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                HomeView().tag(AppTab.home).tabItem { Label("Главная", systemImage: "flame.fill") }
                FriendsView().tag(AppTab.friends).tabItem { Label("Друзья", systemImage: "person.2.fill") }
                HistoryView().tag(AppTab.history).tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
                SettingsView().tag(AppTab.settings).tabItem { Label("Настройки", systemImage: "gearshape.fill") }
            }
            .tint(UiTheme.accent)
            .preferredColorScheme(.dark)
            .onChange(of: selectedTab) { _, _ in
                guard !reduceMotion else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            if !onboardingComplete {
                OnboardingView(isComplete: $onboardingComplete)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.03)))
                    .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: onboardingComplete)
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

    private enum AppTab: Hashable { case home, friends, history, settings }
}

#Preview { MainTabView() }
