import SwiftUI
import UIKit

struct HomeView: View {
    @State private var store = AppStore.shared
    @State private var session = SessionStore.shared
    @State private var showingLogin = false
    @State private var confirmLogout = false

    @State private var runActive = false
    @State private var progressText = ""
    @State private var progressDone = 0
    @State private var progressTotal = 0
    @State private var runSummary: RunRecord?
    @State private var showSummary = false

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
                    VStack(spacing: 10) {
                        Button {
                            startRun()
                        } label: {
                            Label("Продлить сейчас", systemImage: "flame.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(!session.isLoggedIn || runActive)

                        Text(statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Огонёк")
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
            .fullScreenCover(isPresented: $runActive) {
                RunOverlay(text: progressText, done: progressDone, total: progressTotal)
            }
            .alert("Готово", isPresented: $showSummary) {
                Button("Ок", role: .cancel) {}
            } message: {
                if let run = runSummary {
                    Text("Отправлено: \(run.sentCount), ошибок: \(run.failedCount)")
                }
            }
        }
    }

    private var statusLine: String {
        if runActive { return "Идёт прогон…" }
        if !session.isLoggedIn { return "Сначала войди в TikTok" }
        if store.friendsDueToday.isEmpty { return "Сегодня всё отправлено 🔥" }
        return "Отправит сообщение \(store.friendsDueToday.count) друзьям"
    }

    private func startRun() {
        runActive = true
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            let record = await StreakEngine.run { update in
                progressText = update.text
                progressDone = update.done
                progressTotal = update.total
            }
            UIApplication.shared.isIdleTimerDisabled = false
            runActive = false
            runSummary = record
            showSummary = !record.results.isEmpty
        }
    }
}

struct RunOverlay: View {
    let text: String
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                    .padding(.bottom, 4)
                Text("Продлеваю огоньки…")
                    .font(.title2.bold())
                Text(text)
                    .foregroundStyle(.secondary)
                if total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                        .padding(.horizontal, 40)
                    Text("\(done) из \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Не переключайся из приложения — так надёжнее")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
