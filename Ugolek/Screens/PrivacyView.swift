import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Section {
                    Text("Уголёк работает локально на вашем iPhone. Никакие данные не отправляются на серверы — потому что серверов нет.")
                } header: { Text("Принцип") }

                Section {
                    Text("• Логин и куки TikTok хранятся в Keychain устройства.\n• Список друзей и история прогонов — в локальных файлах приложения.\n• Сообщения отправляются через скрытый WKWebView прямо на tiktok.com — как если бы вы делали это вручную в браузере.\n• Никакие сторонние API, аналитика или трекеры не используются.")
                } header: { Text("Что хранится") }

                Section {
                    Text("Уголёк не видит и не хранит ваш пароль TikTok. Вход происходит в официальном WebView TikTok — приложение сохраняет только куки сессии, чтобы не просить вход каждый раз.")
                } header: { Text("Вход в TikTok") }

                Section {
                    Text("Уголёк — неофициальное приложение, не связанное с TikTok. Использование автоматизации может нарушать правила TikTok. Вы используете приложение на свой риск.")
                } header: { Text("Дисклеймер") }
            }
            .padding()
        }
        .navigationTitle("Приватность")
        .navigationBarTitleDisplayMode(.inline)
    }
}
