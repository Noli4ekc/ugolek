import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var store = AppStore.shared

    private let accent = Color.orange
    private let pageBackground = Color.black

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Настрой всё один раз — дальше Уголёк работает сам.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.horizontal, 4)

                    SettingCard(
                        title: "Сообщение",
                        icon: "bubble.left.and.bubble.right.fill",
                        footer: store.settings.useRandomMessages
                            ? "Уголёк берёт короткую фразу из пула (~30 вариантов) и отправляет разную каждому другу — без повторов подряд."
                            : "Это сообщение Уголёк отправит каждому другу. Не слишком длинное — как обычное «пиши мне»."
                    ) {
                        Toggle("Случайные фразы", isOn: $store.settings.useRandomMessages)
                            .tint(accent)
                            .accessibilityHint("Отправлять разные сообщения каждому другу")

                        if !store.settings.useRandomMessages {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Текст сообщения")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.52))

                                TextField("Напиши короткое сообщение", text: $store.settings.messageText, axis: .vertical)
                                    .lineLimit(1...3)
                                    .font(.body)
                                    .foregroundStyle(.white)
                                    .tint(accent)
                                    .padding(12)
                                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    SettingCard(
                        title: "Расписание",
                        icon: "clock.fill",
                        footer: "Каждый день в это время Уголёк пришлёт уведомление: тапнешь — и он продлит все огоньки."
                    ) {
                        DatePicker("Время напоминания", selection: dailyTime, displayedComponents: .hourAndMinute)
                            .tint(accent)
                            .datePickerStyle(.compact)
                    }

                    SettingCard(
                        title: "Фоновый режим",
                        icon: "location.fill",
                        footer: "Включён — Уголёк сам продлевает огоньки каждый день в выбранное время, не открываясь и не спрашивая. Держит геолокацию минимальной точности (вышки связи, не GPS) — батарея расходуется чуть быстрее, синяя стрелка видна в статус-баре. Перед включением прогонит проверку без отправки сообщений. После перезагрузки телефона открой Уголёк один раз."
                    ) {
                        Toggle("Гео всегда (авто-продление)", isOn: $store.settings.geoAlwaysAuto)
                            .tint(accent)
                            .accessibilityHint("Автоматически продлевать огоньки через геолокацию")
                            .onChange(of: store.settings.geoAlwaysAuto) { _, enabled in
                                handleGeoToggle(enabled)
                            }

                        if store.settings.geoAlwaysAuto {
                            if let next = AutoRunner.shared.nextRunDate {
                                SettingValueRow(title: "Следующий прогон", value: next.formatted(date: .omitted, time: .shortened))
                            }

                            if LocationKeeper.shared.permissionStatus != .authorizedAlways {
                                Label("Нужно разрешение «Всегда» на геолокацию — нажми тумблер ещё раз", systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    SettingCard(
                        title: "Поведение",
                        icon: "slider.horizontal.3",
                        footer: "Пропускать недоступных — если чат друга не нашёлся, прогон продолжится с остальными. «Только с огоньком» — письма уходят лишь друзьям с включённым флажком 🔥 (в веб-версии TikTok огонёк не отображается, поэтому он отмечается вручную у каждого друга). Быстрый режим — короче паузы между друзьями (~3–4 раза быстрее); чуть выше риск, что TikTok заподозрит автоматизацию."
                    ) {
                        Toggle("Пропускать недоступных", isOn: $store.settings.skipUnreachable)
                            .tint(accent)
                            .accessibilityHint("Пропускать друзей с недоступным чатом")
                        Toggle("Только тем, у кого есть огонёк", isOn: $store.settings.messageOnlyWithFlame)
                            .tint(accent)
                            .accessibilityHint("Отправлять сообщения только друзьям с огоньком")
                        Toggle("Быстрый режим", isOn: $store.settings.fastMode)
                            .tint(accent)
                            .accessibilityHint("Ускорить прогон, увеличивая риск блокировки")
                    }

                    SettingCard(
                        title: "Доставка",
                        icon: "checkmark.shield.fill",
                        footer: "Перед отправкой Уголёк открывает чат и сверяет @юзернейм — защита от одинаковых имён и ошибочной доставки не тому. Если TikTok изменит вёрстку и доставка сломается (в истории массово «не удалось проверить») — выключи: вернётся старый поиск по имени."
                    ) {
                        Toggle("Проверять получателя", isOn: $store.settings.recipientVerification)
                            .tint(accent)
                            .accessibilityHint("Сверять юзернейм перед отправкой сообщения")
                    }

                    SettingCard(
                        title: "Автоматизация без тапа",
                        icon: "bolt.fill",
                        footer: "В выбранное время iPhone сам запустит фоновый прогон и пришлёт итог уведомлением — если телефон разблокирован; на заблокированном выполнится сразу после разблокировки. Напоминание-уведомление остаётся запасным вариантом."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            AutomationStep(number: 1, text: "Открой приложение «Команды» → Автоматизации → «+»")
                            AutomationStep(number: 2, text: "Триггер: «Время суток» — выбери удобное время")
                            AutomationStep(number: 3, text: "Действие: «Продлить огоньки (фон)» (приложение Уголёк) — не открывает приложение")
                            AutomationStep(number: 4, text: "Отключи «Спрашивать до запуска» → «Готово»")
                        }
                    }

                    SettingCard(title: "О приложении", icon: "lock.shield.fill", footer: nil) {
                        NavigationLink {
                            PrivacyView()
                        } label: {
                            Label("Приватность", systemImage: "lock.shield")
                                .foregroundStyle(.white)
                        }
                        .tint(.white)
                        .accessibilityHint("Открыть политику приватности")

                        SettingValueRow(
                            title: "Версия",
                            value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
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

#Preview("Settings") {
    SettingsView()
        .preferredColorScheme(.dark)
}

private struct SettingCard<Content: View>: View {
    let title: String
    let icon: String
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(title: String, icon: String, footer: String?, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 0) {
                content()
            }
            .padding(16)
            .background(Color.white.opacity(0.085), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

private struct SettingValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.72))
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.48))
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

private struct AutomationStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Color.orange, in: Circle())

            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
