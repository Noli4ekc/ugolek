import SwiftUI
import UserNotifications

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
                    Toggle("Гео всегда (авто-продление)", isOn: $store.settings.geoAlwaysAuto)
                        .onChange(of: store.settings.geoAlwaysAuto) { _, enabled in
                            handleGeoToggle(enabled)
                        }
                    if store.settings.geoAlwaysAuto {
                        if let next = AutoRunner.shared.nextRunDate {
                            LabeledContent("Следующий прогон", value: next.formatted(date: .omitted, time: .shortened))
                        }
                        if LocationKeeper.shared.permissionStatus != .authorizedAlways {
                            Text("Нужно разрешение «Всегда» на геолокацию — нажми тумблер ещё раз")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Фоновый режим")
                } footer: {
                    Text("Включён — Уголёк сам продлевает огоньки каждый день в выбранное время, не открываясь и не спрашивая. Держит геолокацию минимальной точности (вышки связи, не GPS) — батарея расходуется чуть быстрее, синяя стрелка видна в статус-баре. Перед включением прогонит проверку без отправки сообщений. После перезагрузки телефона открой Уголёк один раз.")
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
                    Toggle("Проверять получателя", isOn: $store.settings.recipientVerification)
                } header: {
                    Text("Доставка")
                } footer: {
                    Text("Перед отправкой Уголёк открывает чат и сверяет @юзернейм — защита от одинаковых имён и ошибочной доставки не тому. Если TikTok изменит вёрстку и доставка сломается (в истории массово «не удалось проверить») — выключи: вернётся старый поиск по имени.")
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
                ReminderService.shared.scheduleDaily(force: true)
                AutoRunner.shared.reschedule()
            }
        )
    }

    // Включение «Гео всегда»: запрос разрешения + тестовый dry-run без отправки.
    // Пока тест идёт, юзер может передумать: применяем результат, только если
    // тумблер всё ещё включён — иначе поздний успех включил бы режим поверх OFF.
    private func handleGeoToggle(_ enabled: Bool) {
        if enabled {
            LocationKeeper.shared.requestAlways()
            Task {
                let ok = await runDryTest()
                guard store.settings.geoAlwaysAuto else {
                    postNotice("Включение отменено — режим выключили во время проверки")
                    return
                }
                if ok {
                    LocationKeeper.shared.startPersistent()
                    AutoRunner.shared.arm()
                    postNotice("Фон готов: \(AppStore.shared.friendsDueToday.count) друзей ждут 🔥")
                } else {
                    store.settings.geoAlwaysAuto = false
                    postNotice(SessionStore.shared.isLoggedIn
                        ? "Тестовый прогон не прошёл — проверь связь и попробуй ещё раз"
                        : "Нужен вход в TikTok — войди и включи фон заново")
                }
            }
        } else {
            AutoRunner.shared.disarm()
            LocationKeeper.shared.stopPersistent()
        }
    }

    private func runDryTest() async -> Bool {
        guard SessionStore.shared.isLoggedIn else { return false }
        guard !AppStore.shared.friendsDueToday.isEmpty else { return true }
        let record = await RunCoordinator.shared.startDryTest()
        return record.sentCount > 0 || record.skippedCount > 0 || record.failedCount == 0
    }

    private func postNotice(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Уголёк"
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "ugolek.geoTest",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}
