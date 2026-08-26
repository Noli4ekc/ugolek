import SwiftUI

// Дизайн в духе Opal для Уголька — открыть в Xcode Canvas (⌘⌥P),
// выбрать «DesignPreview» и перелистывать страницы.
// Ничего из рабочего кода не трогает: это отдельный файл-витрина.

struct DesignPreview: View {
    var body: some View {
        TabView {
            OnboardingDemo()
                .tabItem { Label("Онбординг", systemImage: "sparkles") }
            HomeDemo()
                .tabItem { Label("Главная", systemImage: "flame.fill") }
            FriendsDemo()
                .tabItem { Label("Друзья", systemImage: "person.2.fill") }
            HistoryDemo()
                .tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
            SettingsDemo()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
        .tint(UiTheme.accent)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Онбординг: «Уголёк раскрывает свой огонь…»

struct OnboardingDemo: View {
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(page == 0
                 ? "Уголёк раскрывает свой\nогонь тем, кто замедляется\nи смотрит внимательно."
                 : "Твои стрики —\nэто инструмент.")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.4)
                .multilineTextAlignment(.center)
                .foregroundStyle(UiTheme.text)
                .padding(.horizontal, 32)
                .animation(.easeInOut(duration: 0.4), value: page)

            GemView()
                .padding(.vertical, 40)

            Text(page == 0 ? "НАЖМИ, ЧТОБЫ ПРОДОЛЖИТЬ" : "НАЖМИ, ЧТОБЫ ПРОДОЛЖИТЬ")
                .font(.system(size: 12, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(UiTheme.text.opacity(0.8))
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UiTheme.background.ignoresSafeArea())
        .onTapGesture { withAnimation { page.toggle() } }
    }
}

// Камень-опал: многослойный градиент внутри органической формы.
// В реальном приложении это будет 3D-рендер/Metal-шейдер — тут только форма и цвет.
struct GemView: View {
    var size: CGFloat = 140

    @State private var hue = 0.0

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.44, style: .continuous)
            .fill(
                AngularGradient(
                    colors: [
                        Color(red: 0.65, green: 0.55, blue: 0.98),
                        Color(red: 0.38, green: 0.65, blue: 0.98),
                        Color(red: 0.20, green: 0.83, blue: 0.60),
                        Color(red: 0.98, green: 0.57, blue: 0.24),
                        Color(red: 0.65, green: 0.55, blue: 0.98),
                    ],
                    center: .center,
                    angle: .degrees(hue)
                )
            )
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.35), .clear, .black.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-12))
            .shadow(color: Color(red: 0.65, green: 0.55, blue: 0.98).opacity(0.4), radius: 30)
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: true)) {
                    hue = 360
                }
            }
    }
}

// MARK: - Главная

struct HomeDemo: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: "Уголёк", subtitle: "Все стрики продлены")

                // Огромное число
                VStack(spacing: 6) {
                    Text("12")
                        .font(.system(size: 96, weight: .heavy))
                        .kerning(-6)
                        .foregroundStyle(UiTheme.accent)
                    Text("дней подряд")
                        .font(.system(size: 15))
                        .foregroundStyle(UiTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)

                // Три метрики
                HStack(spacing: 10) {
                    MetricCard(value: "5", label: "друзей", color: UiTheme.accent)
                    MetricCard(value: "3", label: "сегодня", color: UiTheme.success)
                    MetricCard(value: "48м", label: "экономии", color: UiTheme.text)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

                // Список друзей
                Text("Друзья")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(UiTheme.textFaint)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                VStack(spacing: 0) {
                    DemoFriend(name: "Алиса", handle: "@alisa_k", days: 12, color: UiTheme.accent)
                    DemoFriend(name: "Максим", handle: "@maxim_s", days: 8, color: .blue)
                    DemoFriend(name: "Даша", handle: "@dasha_m", days: 5, color: .pink)
                    DemoFriend(name: "Кирилл", handle: "@kirill_v", days: 3, color: UiTheme.success)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                UgolekButton(title: "Отправить сейчас", filled: true) {}
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .padding(.bottom, 24)
        }
        .background(UiTheme.background.ignoresSafeArea())
    }
}

private struct MetricCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .heavy))
                .kerning(-1.5)
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .kerning(0.5)
                .foregroundStyle(UiTheme.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 14).fill(UiTheme.surface))
    }
}

private struct DemoFriend: View {
    let name: String
    let handle: String
    let days: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)
                .overlay(Text(handle.dropFirst().first.map(String.init) ?? "?").font(.system(size: 16, weight: .bold)).foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(UiTheme.text)
                Text(handle)
                    .font(.system(size: 12))
                    .foregroundStyle(UiTheme.textFaint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(days)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(UiTheme.accent)
                Text("дней")
                    .font(.system(size: 9))
                    .kerning(0.5)
                    .foregroundStyle(UiTheme.textFaint)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.06)
        }
    }
}

// MARK: - Друзья

struct FriendsDemo: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: "Друзья", subtitle: "5 активных из 7")
                VStack(spacing: 0) {
                    DemoFriend(name: "Алиса", handle: "@alisa_k", days: 12, color: UiTheme.accent)
                    DemoFriend(name: "Максим", handle: "@maxim_s", days: 8, color: .blue)
                    DemoFriend(name: "Даша", handle: "@dasha_m", days: 5, color: .pink)
                    DemoFriend(name: "Кирилл", handle: "@kirill_v", days: 3, color: UiTheme.success)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(UiTheme.background.ignoresSafeArea())
    }
}

// MARK: - История

struct HistoryDemo: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: "История")

                Text("СЕГОДНЯ")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(UiTheme.textFaint)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)

                VStack(spacing: 8) {
                    HistoryRow(name: "Алиса", message: "«Привет! Как дела?»", time: "20:01", ok: true)
                    HistoryRow(name: "Максим", message: "«С добрым утром!»", time: "20:02", ok: true)
                    HistoryRow(name: "Даша", message: "«Хорошего дня!»", time: "20:03", ok: true)
                }
                .padding(.horizontal, 24)

                Text("ВЧЕРА")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(UiTheme.textFaint)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 10)

                VStack(spacing: 8) {
                    HistoryRow(name: "Алиса", message: "«Добрый вечер!»", time: "20:00", ok: true)
                    HistoryRow(name: "Кирилл", message: "Стрик уже продлён", time: "—", ok: false)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(UiTheme.background.ignoresSafeArea())
    }
}

private struct HistoryRow: View {
    let name: String
    let message: String
    let time: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark" : "pause")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ok ? UiTheme.success : UiTheme.textFaint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(ok ? UiTheme.success.opacity(0.12) : UiTheme.surface))

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(UiTheme.text)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(UiTheme.textFaint)
                    .lineLimit(1)
            }
            Spacer()
            Text(time)
                .font(.system(size: 11))
                .foregroundStyle(UiTheme.textFaint.opacity(0.7))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(UiTheme.surface))
    }
}

// MARK: - Настройки

struct SettingsDemo: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle(text: "Настройки")

                settingsGroup("Аккаунт") {
                    SettingsRow(icon: "flame.fill", iconColor: UiTheme.accent, title: "TikTok", value: "Активен")
                    SettingsRow(icon: "person.fill", iconColor: UiTheme.textMuted, title: "Никнейм", value: "@kirill_v")
                }
                settingsGroup("Расписание") {
                    SettingsRow(icon: "clock.fill", iconColor: UiTheme.success, title: "Время отправки", value: "20:00")
                    SettingsRow(icon: "dice.fill", iconColor: UiTheme.textMuted, title: "Дрожание времени", value: "±15 мин")
                }
                settingsGroup("Сообщения") {
                    SettingsRow(icon: "bubble.left.fill", iconColor: UiTheme.accent, title: "Стиль сообщений", value: "Дружелюбный")
                    SettingsRow(icon: "text.quote", iconColor: UiTheme.textMuted, title: "Пул фраз", value: "30 фраз")
                }
                settingsGroup("Режим работы") {
                    SettingsRow(icon: "location.fill", iconColor: UiTheme.success, title: "Гео всегда", value: "Выкл")
                    SettingsRow(icon: "bolt.fill", iconColor: UiTheme.textMuted, title: "Быстрый режим", value: "Выкл")
                }
            }
            .padding(.bottom, 24)
        }
        .background(UiTheme.background.ignoresSafeArea())
    }

    private func settingsGroup<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(UiTheme.textFaint)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

            VStack(spacing: 0) { content() }
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .background(RoundedRectangle(cornerRadius: 14).fill(UiTheme.surface))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

#Preview("Дизайн Уголька") {
    DesignPreview()
}
