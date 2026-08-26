import SwiftUI

struct HomeView: View {
    @State private var store = AppStore.shared
    @State private var session = SessionStore.shared
    @State private var coordinator = RunCoordinator.shared
    @State private var showingLogin = false
    @State private var confirmLogout = false
    @State private var diagActive = false
    @State private var diagText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var coordinator = coordinator
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ScreenTitle("Уголёк", subtitle: "Огоньки под присмотром — без лишнего шума")
                    accountCard
                    todayCard
                    actionCard
                }
                .padding(.bottom, 30)
            }
            .background(UiTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingLogin) { LoginView() }
            .confirmationDialog("Выйти из TikTok?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { session.logout() }
                Button("Отмена", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $coordinator.runActive) {
                RunOverlay(text: coordinator.progressText, done: coordinator.progressDone, total: coordinator.progressTotal)
            }
            .alert("Готово", isPresented: $coordinator.showSummary) {
                Button("Ок", role: .cancel) {}
            } message: {
                if let run = coordinator.lastSummary {
                    if run.failedCount > 0, let firstError = run.results.first(where: { $0.status == .failed })?.detail {
                        Text("Отправлено: \(run.sentCount), ошибок: \(run.failedCount). Первая ошибка: \(firstError). Подробности — во вкладке «История».")
                    } else { Text("Отправлено: \(run.sentCount), ошибок: \(run.failedCount)") }
                }
            }
            .sheet(item: Binding(get: { diagText.map { DiagReport(text: $0) } }, set: { _ in diagText = nil })) { report in
                DiagSheet(text: report.text)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var accountCard: some View {
        UgolekCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Image(systemName: session.isLoggedIn ? "checkmark.shield.fill" : "lock.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(session.isLoggedIn ? UiTheme.success : UiTheme.accent)
                        .frame(width: 42, height: 42)
                        .background((session.isLoggedIn ? UiTheme.success : UiTheme.accent).opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.isLoggedIn ? "TikTok подключён" : "Подключи TikTok")
                            .font(.headline.weight(.semibold)).foregroundStyle(UiTheme.text)
                        Text(session.isLoggedIn ? "Сессия активна и готова к работе" : "Вход нужен для продления огоньков")
                            .font(.subheadline).foregroundStyle(UiTheme.textMuted)
                    }
                    Spacer()
                }
                if let checked = session.lastChecked {
                    Text("Проверено сегодня в \(checked, format: .dateTime.hour().minute())")
                        .font(.caption).foregroundStyle(UiTheme.textFaint)
                }
                UgolekButton(session.isLoggedIn ? "Выйти из аккаунта" : "Войти в TikTok", systemImage: session.isLoggedIn ? "rectangle.portrait.and.arrow.right" : "arrow.right", prominent: !session.isLoggedIn) {
                    if session.isLoggedIn { confirmLogout = true } else { showingLogin = true }
                }
                .accessibilityHint(session.isLoggedIn ? "Отключить аккаунт TikTok" : "Подключить аккаунт TikTok")
            }
        }
        .padding(.horizontal, UiTheme.screenPadding)
    }

    private var todayCard: some View {
        UgolekCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("СЕГОДНЯ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(UiTheme.textFaint)
                    Spacer()
                    Image(systemName: "flame.fill").foregroundStyle(UiTheme.accent)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(store.sentTodayCount)").font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(UiTheme.text)
                    Text("из \(store.friends.filter(\.isEnabled).count) друзей").font(.subheadline).foregroundStyle(UiTheme.textMuted)
                }
                ProgressView(value: Double(store.sentTodayCount), total: Double(max(store.friends.filter(\.isEnabled).count, 1)))
                    .tint(UiTheme.accent)
                    .scaleEffect(y: 1.5)
                Text(statusLine).font(.subheadline).foregroundStyle(UiTheme.textMuted)
            }
        }
        .padding(.horizontal, UiTheme.screenPadding)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: store.sentTodayCount)
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ДЕЙСТВИЯ").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(UiTheme.textFaint).padding(.horizontal, UiTheme.screenPadding)
            UgolekCard {
                VStack(spacing: 10) {
                    UgolekButton("Продлить сейчас", systemImage: "flame.fill", prominent: true) { coordinator.start() }
                        .disabled(!session.isLoggedIn || coordinator.runActive)
                        .opacity(session.isLoggedIn ? 1 : 0.45)
                    Text(session.isLoggedIn ? "Уголёк отправит сообщения друзьям из очереди" : "Сначала войди в TikTok")
                        .font(.caption).foregroundStyle(UiTheme.textMuted).frame(maxWidth: .infinity)
                    Button { runDiagnostics() } label: {
                        Label(diagActive ? "Проверяю…" : "Диагностика соединения", systemImage: "stethoscope")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .foregroundStyle(UiTheme.textMuted).background(UiTheme.button, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(diagActive || !session.isLoggedIn)
                    .accessibilityHint("Проверить соединение с TikTok")
                }
            }
            .padding(.horizontal, UiTheme.screenPadding)
        }
    }

    private var statusLine: String {
        if coordinator.runActive { return "Идёт прогон…" }
        if !session.isLoggedIn { return "Сессия пока не подключена" }
        if store.friendsDueToday.isEmpty { return "Сегодня всё отправлено — огонёк горит" }
        return "В очереди ещё \(store.friendsDueToday.count) \(store.friendsDueToday.count == 1 ? "друг" : "друзей")"
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data), let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), let text = String(data: encoded, encoding: .utf8) else { return raw }
        return text
    }

    private func runDiagnostics() {
        guard !coordinator.runActive else { diagText = "Идёт прогон — диагностика недоступна. Попробуй после завершения."; return }
        diagActive = true
        Task {
            var parts: [String] = []
            do {
                try await InboxRunner.shared.ensureLoaded()
                for attempt in 1...2 {
                    let raw = await InboxRunner.shared.discovery()
                    parts.append("=== Список чатов (попытка \(attempt)) ===\n" + prettyJSON(raw))
                    if attempt < 2 { try? await Task.sleep(for: .seconds(6)) }
                }
                let probe = await InboxRunner.shared.chatProbe()
                parts.append("=== Открытый чат (снимок) ===\n" + prettyJSON(probe))
                diagText = parts.joined(separator: "\n\n")
            } catch { diagText = "Не удалось загрузить страницу сообщений:\n\((error as? LocalizedError)?.errorDescription ?? String(describing: error))" }
            diagActive = false
        }
    }
}

struct DiagReport: Identifiable { let text: String; var id: String { text } }

#Preview("Logged Out") {
    HomeView()
        .preferredColorScheme(.dark)
}

#Preview("With Data") {
    HomeView()
        .preferredColorScheme(.dark)
}

struct DiagSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { ScrollView { Text(text).font(.system(size: 13, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled) }.background(UiTheme.background).navigationTitle("Диагностика").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } } }
        .preferredColorScheme(.dark)
    }
}

struct RunOverlay: View {
    let text: String; let done: Int; let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack { UiTheme.background.ignoresSafeArea(); VStack(spacing: 18) {
            Image(systemName: "flame.fill").font(.system(size: 58)).foregroundStyle(UiTheme.accent).symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            Text("Продлеваю огоньки…").font(.title2.bold()).foregroundStyle(UiTheme.text)
            Text(text).foregroundStyle(UiTheme.textMuted).multilineTextAlignment(.center)
            if total > 0 { ProgressView(value: Double(done), total: Double(total)).tint(UiTheme.accent).padding(.horizontal, 40); Text("\(done) из \(total)").font(.caption).foregroundStyle(UiTheme.textMuted) }
            Text("Не закрывай приложение — так надёжнее").font(.caption2).foregroundStyle(UiTheme.textFaint)
        }.padding(28) }
    }
}
