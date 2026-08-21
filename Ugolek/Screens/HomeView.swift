import SwiftUI

struct HomeView: View {
    @State private var store = AppStore.shared
    @State private var session = SessionStore.shared
    @State private var showingLogin = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(session.isLoggedIn ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(session.isLoggedIn ? "Сессия TikTok активна" : "Требуется вход в TikTok")
                        Spacer()
                        if session.isLoggedIn {
                            Button("Выйти", role: .destructive) {
                                confirmLogout = true
                            }
                        } else {
                            Button("Войти") {
                                showingLogin = true
                            }
                        }
                    }
                } header: {
                    Text("Аккаунт")
                } footer: {
                    if let checked = session.lastChecked {
                        Text("Проверено: \(checked, format: .dateTime.hour().minute())")
                    }
                }

                Section {
                    LabeledContent("Всего друзей", value: "\(store.friends.count)")
                    LabeledContent(
                        "Отправлено сегодня",
                        value: "\(store.sentTodayCount) из \(store.friends.filter(\.isEnabled).count)"
                    )
                } header: {
                    Text("Сегодня")
                }

                Section {
                    ContentUnavailableView(
                        "Движок в разработке",
                        systemImage: "flame",
                        description: Text("Кнопка «Продлить сейчас» появится, когда будет готов движок отправки")
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Уголёк")
            .sheet(isPresented: $showingLogin) {
                LoginView()
            }
            .confirmationDialog("Выйти из TikTok?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) {
                    session.logout()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }
}
