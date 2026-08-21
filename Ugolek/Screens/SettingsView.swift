import SwiftUI

struct SettingsView: View {
    @State private var store = AppStore.shared

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Текст сообщения",
                        text: $store.settings.messageText,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                } header: {
                    Text("Сообщение")
                } footer: {
                    Text("Это сообщение Уголёк отправит каждому другу. Не слишком длинное — как обычное «пиши мне».")
                }

                Section {
                    DatePicker(
                        "Время напоминания",
                        selection: dailyTime,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    Text("Расписание")
                } footer: {
                    Text("Каждый день в это время Уголёк пришлёт уведомление: тапнешь — и он продлит все огоньки.")
                }

                Section {
                    Toggle("Случайные фразы", isOn: $store.settings.useRandomMessages)
                    Toggle("Пропускать недоступных", isOn: $store.settings.skipUnreachable)
                } header: {
                    Text("Поведение")
                } footer: {
                    Text("Случайные фразы — вместо одного текста Уголёк берёт короткую фразу из пула. Пропускать недоступных — если чат друга не нашёлся, прогон продолжится с остальными.")
                }

                Section {
                    LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }
            }
            .navigationTitle("Настройки")
        }
    }

    private var dailyTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: store.settings.dailyHour,
                    minute: store.settings.dailyMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.settings.dailyHour = c.hour ?? 10
                store.settings.dailyMinute = c.minute ?? 0
            }
        )
    }
}
