import SwiftUI

struct SettingsView: View {
    @State private var store = AppStore.shared

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    Toggle("Случайные фразы", isOn: $store.settings.useRandomMessages)
                    if !store.settings.useRandomMessages {
                        TextField(
                            "Текст сообщения",
                            text: $store.settings.messageText,
                            axis: .vertical
                        )
                        .lineLimit(1...3)
                    }
                } header: {
                    Text("Сообщение")
                } footer: {
                    if store.settings.useRandomMessages {
                        Text("Уголёк берёт короткую фразу из пула (~30 вариантов) и отправляет разную каждому другу — без повторов подряд.")
                    } else {
                        Text("Это сообщение Уголёк отправит каждому другу. Не слишком длинное — как обычное «пиши мне».")
                    }
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
                    Toggle("Пропускать недоступных", isOn: $store.settings.skipUnreachable)
                    Toggle("Только тем, у кого есть огонёк", isOn: $store.settings.messageOnlyWithFlame)
                    Toggle("Быстрый режим", isOn: $store.settings.fastMode)
                } header: {
                    Text("Поведение")
                } footer: {
                    Text("Пропускать недоступных — если чат друга не нашёлся, прогон продолжится с остальными. «Только с огоньком» — письма уходят лишь друзьям с включённым флажком 🔥 (в веб-версии TikTok огонёк не отображается, поэтому он отмечается вручную у каждого друга). Быстрый режим — короче паузы между друзьями (~3–4 раза быстрее); чуть выше риск, что TikTok заподозрит автоматизацию.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Открой приложение «Команды» → Автоматизации → «+»")
                        Text("2. Триггер: «Время суток» — выбери удобное время")
                        Text("3. Действие: «Продлить огоньки (фон)» (приложение Уголёк) — не открывает приложение")
                        Text("4. Отключи «Спрашивать до запуска» → «Готово»")
                    }
                    .font(.callout)
                } header: {
                    Text("Автоматизация без тапа")
                } footer: {
                    Text("В выбранное время iPhone сам запустит фоновый прогон и пришлёт итог уведомлением — если телефон разблокирован; на заблокированном выполнится сразу после разблокировки. Напоминание-уведомление остаётся запасным вариантом.")
                }

                Section {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Приватность", systemImage: "lock.shield")
                    }
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
