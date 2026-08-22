import SwiftUI

struct HomeView: View {
    @State private var store = AppStore.shared
    @State private var session = SessionStore.shared
    @State private var coordinator = RunCoordinator.shared
    @State private var showingLogin = false
    @State private var confirmLogout = false
    @State private var diagActive = false
    @State private var diagText: String?

    var body: some View {
        @Bindable var coordinator = coordinator
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
                            coordinator.start()
                        } label: {
                            Label("Продлить сейчас", systemImage: "flame.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(!session.isLoggedIn || coordinator.runActive)

                        Text(statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            runDiagnostics()
                        } label: {
                            Label("Диагностика", systemImage: "stethoscope")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                        .disabled(diagActive || !session.isLoggedIn)
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
            .fullScreenCover(isPresented: $coordinator.runActive) {
                RunOverlay(
                    text: coordinator.progressText,
                    done: coordinator.progressDone,
                    total: coordinator.progressTotal
                )
            }
            .alert("Готово", isPresented: $coordinator.showSummary) {
                Button("Ок", role: .cancel) {}
            } message: {
                if let run = coordinator.lastSummary {
                    if run.failedCount > 0,
                       let firstError = run.results.first(where: { $0.status == .failed })?.detail {
                        Text("Отправлено: \(run.sentCount), ошибок: \(run.failedCount). Первая ошибка: \(firstError). Подробности — во вкладке «История».")
                    } else {
                        Text("Отправлено: \(run.sentCount), ошибок: \(run.failedCount)")
                    }
                }
            }
            .sheet(item: Binding(
                get: { diagText.map { DiagReport(text: $0) } },
                set: { _ in diagText = nil }
            )) { report in
                DiagSheet(text: report.text)
            }
        }
    }

    private var statusLine: String {
        if coordinator.runActive { return "Идёт прогон…" }
        if !session.isLoggedIn { return "Сначала войди в TikTok" }
        if store.friendsDueToday.isEmpty { return "Сегодня всё отправлено 🔥" }
        return "Отправит сообщение \(store.friendsDueToday.count) друзьям"
    }

    private func runDiagnostics() {
        diagActive = true
        Task {
            var parts: [String] = []
            do {
                try await InboxRunner.shared.ensureLoaded()
                for attempt in 1...3 {
                    let raw = await InboxRunner.shared.discovery()
                    let pretty: String
                    if let data = raw.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data),
                       let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                       let text = String(data: encoded, encoding: .utf8) {
                        pretty = text
                    } else {
                        pretty = raw
                    }
                    parts.append("=== Попытка \(attempt) ===\n\(pretty)")
                    if attempt < 3 {
                        try? await Task.sleep(for: .seconds(8))
                    }
                }
                diagText = parts.joined(separator: "\n\n")
            } catch {
                diagText = "Не удалось загрузить страницу сообщений:\n\((error as? LocalizedError)?.errorDescription ?? String(describing: error))"
            }
            diagActive = false
        }
    }
}

struct DiagReport: Identifiable {
    let text: String
    var id: String { text }
}

struct DiagSheet: View {
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("Диагностика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { }
                }
            }
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
