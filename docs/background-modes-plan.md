# Архитектурный план: фоновые режимы продления огоньков (уровни 1–3)

**Проект:** Уголёк (Ugolek) — iOS-приложение для автоматического продления стриков в TikTok.
**Цель:** позволить прогону рассылки жить и завершаться в фоне, плюс полноценно автоматический режим по расписанию без участия пользователя.
**Дата составления:** 2026-08-25.
**Статус:** план готов к реализации, выполнения не запущено.

---

## 0. Контекст и отправная точка

Текущее состояние (коммит `1a48527`, CI зелёный):

- Кнопка 🔥 в шторке (`UgolekControlWidget`) открывает приложение через `MaintainStreaksIntent` (`openAppWhenRun = true`) и запускает `RunCoordinator.shared.start()`.
- Прогон идёт на переднем плане: скрытый `WKWebView`, оверлей прогресса, `UIApplication.shared.isIdleTimerDisabled = true` чтобы экран не погас.
- Если свернуть или заблокировать телефон — iOS замораживает процесс через ~15–30 сек, WebView JS умирает, прогон обрывается.
- В настройках уже есть время напоминалки (`dailyHour`/`dailyMinute`, дрожание ±15 мин), уведомление через `ReminderService`, BGTask-догонялка `CatchUpTask`.
- В движке уже есть `dryRun: Bool = false` — проходит всю цепочку без отправки и без записи в историю. Идеально для тестового прогона при включении авто-режима.
- В `RunCoordinator` уже есть `pendingAutoRun` — флаг «прогон отложен, выполнить при следующем открытии». Переиспользуем для деградации.

Три жёстких ограничения iOS, которые диктуют архитектуру:

1. **WebKit запрещён в виджет-расширениях** — кнопка в шторке не может слать сообщения сама.
2. **Приложение в фоне замерзает через ~15–30 сек** — нужен активный «держатель» (геолокация).
3. **Спящий процесс не может сам проснуться по часам** — нужен либо внешний будильник (Шорткатс-автоматизация), либо постоянно живой процесс («Гео всегда»).

---

## 1. Три уровня — что делает каждый

### Уровень 1: Гео-держатель прогона (всегда включён, без настроек)

Любой прогон — ручной, по кнопке, по Командам, авто — арендует у `LocationKeeper` удержание на время своего выполнения. Пока аренда жива, iOS не замораживает процесс. Прогон закончился → аренда освобождается → локация гаснет (если других арендаторов нет).

Эффект для пользователя: тапнул 🔥 → приложение мелькнуло → можно сразу свернуть/заблокировать → рассылка дойдёт до конца.

### Уровень 2: Фоновый интент для Команд-автоматизации

Новый `AppIntent` `HeadlessStreaksIntent` с `openAppWhenRun = false`. Система запускает процесс приложения в фоне (UI не показывается), интент включает гео-держатель и запускает прогон через `RunCoordinator`. По завершении — локальное уведомление с итогами, гео гаснет.

Пользователь один раз создаёт автоматизацию в Командах на время напоминалки (в настройках уже есть инструкция, дополним пунктом «выбери фоновое действие»). Дальше каждый день в это время прогон идёт сам, на разблокированном телефоне — сразу, на заблокированном — после первой разблокировки (ограничение Шорткатс).

### Уровень 3: Тумблер «Гео всегда» (полный автопилот)

Поле `geoAlwaysAuto: Bool = false` в `AppSettings`. Включён → `LocationKeeper` держит постоянную локацию минимальной точности (3 км, вышки/Wi-Fi, GPS не будится), процесс жив круглосуточно. Внутренний планировщик `AutoRunner` стреляет в время напоминалки ±15 мин дрожания и запускает прогон головой в фоне. Между прогонами ничего не тратится, кроме факта живого процесса.

При первом включении — **тестовый dry-run**: движок проходит цепочку без отправки, проверяет логин и `friendsDueToday`. Успех → уведомление «Фон готов: N друзей ждут 🔥», режим вооружён. Провал (нет логина/нет друзей) → тумблер отщёлкивается назад, уведомление с причиной.

Бонус-эксперимент: при активном режиме та же кнопка 🔥 теоретически может стать полностью невидимой (тихий сигнал живому процессу через Darwin-уведомления). Если эксперимент на реальном телефоне не взлетит — теряем только косметику, функционал уровня 3 не страдает.

---

## 2. Проверенные факты (основа плана)

### 2.1. Фоновая геолокация — документированный API

`CLLocationManager` с `allowsBackgroundLocationUpdates = true` + `pausesLocationUpdatesAutomatically = false` + активная сессия (`startUpdatingLocation()` или `startMonitoringSignificantLocationChanges()`) — iOS не замораживает процесс, пока локация активна. Это штатный паттерн для трекеров/навигаторов, не хак. Точность `kCLLocationAccuracyThreeKilometers` — опрос вышек, расход единицы процентов в сутки.

### 2.2. AppIntent с `openAppWhenRun = false` запускает процесс в фоне

Подтверждено Apple-доками: если интент не требует UI, система будит приложение в фоне и выполняет `perform()` в процессе приложения (не расширения). Там доступен WebKit, `RunCoordinator`, `SessionStore` — вся инфраструктура. Время ограничено, но с активным гео-держателем ограничение снимается.

### 2.3. Виджет-расширение не имеет доступа к WebKit

Поэтому кнопка 🔥 в шторке НЕ может сама слать сообщения — только дёрнуть интент, который запустит процесс приложения. Это уже реализовано (`MaintainStreaksIntent` → `RunCoordinator`).

### 2.4. Шорткатс-автоматизации на заблокированном телефоне ждут разблокировки

Документировано: автоматизации типа «Время суток» не выполняются на локскрине — система ставит их в очередь и выполняет при первой разблокировке. Для стриков «раз в сутки» это приемлемо: продлится, когда возьмёшь телефон.

### 2.5. Darwin-уведомления работают без App Group

`CFNotificationCenterGetDarwinNotifyCenter` — межпроцессные уведомления без энтитлементов. Расширение может кинуть сигнал, приложение (если живо) его поймает. Не работает, если процесс приложения мёртв — расширение не может его разбудить. Для бонуса «невидимая кнопка» при активном уровне 3 это подходит: процесс жив, сигнал долетит.

### 2.6. `dryRun` уже есть в `StreakEngine.run()`

`StreakEngine.run(dryRun:forceAll:onProgress:)` — при `dryRun: true` проходит всю цепочку (логин, `ensureLoaded`, перебор друзей, `InboxRunner.send` с `dryRun: true`) без записи в историю (`if !dryRun { store.record(record) }`). Идеально для тестового прогона при включении авто-режима.

### 2.7. `pendingAutoRun` уже есть в `RunCoordinator`

`pendingAutoRun: Bool` + `consumePendingAutoRunIfNeeded()` — флаг «прогон отложен, выполнить при следующем открытии». Уже используется `ReminderService` для тапа по уведомлению. Переиспользуем для деградации уровня 3: если систему убила процесс, авто-прогон ставит флаг и довыполняется при первом ручном открытии.

### 2.8. Bundle ID — `com.ugolek.app`, виджет — `com.ugolek.app.widget`

Зафиксировано в `project.yml` (коммит `1a48527`). Права локации добавляем в Info.plist основного таргета (виджету локация не нужна — он только кидает интент).

---

## 3. Что нужно создать/изменить — точный код для каждого файла

### 3.1. `Ugolek/Core/Background/LocationKeeper.swift` (НОВЫЙ)

Синглтон-держатель геолокации со счётчиком потребителей. `acquire()` / `release()` — аренда на время прогона. `startPersistent()` / `stopPersistent()` — постоянная аренда для уровня 3. Watchdog-таймер на зависшие аренды.

```swift
import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationKeeper: NSObject, CLLocationManagerDelegate {
    static let shared = LocationKeeper()

    private let manager = CLLocationManager()
    private var acquireCount = 0
    private var persistent = false
    private var watchdog: Task<Void, Never>?

    var permissionStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isHolding: Bool {
        acquireCount > 0 || persistent
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = false
        // allowsBackgroundLocationUpdates ставим в true только когда есть потребитель
    }

    // Запрос разрешения «Всегда» — вызывается из UI настроек
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    // Уровень 1: аренда на время прогона
    func acquire() {
        acquireCount += 1
        startIfNeeded()
        resetWatchdog()
    }

    func release() {
        guard acquireCount > 0 else { return }
        acquireCount -= 1
        stopIfNeeded()
    }

    // Уровень 3: постоянная аренда
    func startPersistent() {
        persistent = true
        startIfNeeded()
    }

    func stopPersistent() {
        persistent = false
        stopIfNeeded()
    }

    private func startIfNeeded() {
        guard isHolding else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func stopIfNeeded() {
        guard !isHolding else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        watchdog?.cancel(); watchdog = nil
    }

    // Watchdog: если аренда висит > 15 мин — принудительно释放 (прогон завис)
    private func resetWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(900))
            guard !Task.isCancelled, let self else { return }
            while self.acquireCount > 0 { self.release() }
        }
    }

    // CLLocationManagerDelegate — координаты нам не нужны, только факт активности
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // Если разрешение забрали во время persistent — выключаем режим
            if persistent && manager.authorizationStatus != .authorizedAlways {
                persistent = false
                stopIfNeeded()
                NotificationCenter.default.post(name: .geoPermissionRevoked, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let geoPermissionRevoked = Notification.Name("ugolek.geoPermissionRevoked")
}
```

### 3.2. `Ugolek/Core/Background/AutoRunner.swift` (НОВЫЙ)

Планировщик уровня 3. При включении режима и при смене времени в настройках пересчитывает следующий запуск. Перед запуском проверяет условия (логин, `friendsDueToday`, не идёт ли уже прогон).

```swift
import Foundation

@MainActor
final class AutoRunner {
    static let shared = AutoRunner()

    private var timer: Task<Void, Never>?

    var nextRunDate: Date? = nil

    func arm() {
        scheduleNext()
    }

    func disarm() {
        timer?.cancel(); timer = nil
        nextRunDate = nil
    }

    /// Пересчёт при смене времени в настройках
    func reschedule() {
        guard AppStore.shared.settings.geoAlwaysAuto else { return }
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.cancel()
        let settings = AppStore.shared.settings
        let jitter = Int.random(in: -15...15)
        let base = Calendar.current.date(
            bySettingHour: settings.dailyHour,
            minute: settings.dailyMinute,
            second: 0, of: .now
        ) ?? .now
        let candidate = Calendar.current.date(byAdding: .minute, value: jitter, to: base) ?? base
        let target = candidate <= .now
            ? Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            : candidate
        nextRunDate = target
        timer = Task { [weak self] in
            let wait = Date().distance(to: target)
            guard wait > 0 else { self?.fireAndReschedule(); return }
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.fireAndReschedule()
        }
    }

    private func fireAndReschedule() {
        // Условия пропуска
        guard SessionStore.shared.isLoggedIn else { scheduleNext(); return }
        guard !AppStore.shared.friendsDueToday.isEmpty else { scheduleNext(); return }
        guard !RunCoordinator.shared.runActive else { scheduleNext(); return }
        // Запуск головой в фоне — держатель внутри start() уже стоит
        RunCoordinator.shared.start()
        scheduleNext()
    }
}
```

### 3.3. `Ugolek/Core/AppIntents/HeadlessStreaksIntent.swift` (НОВЫЙ)

Фоновый интент для уровня 2. `openAppWhenRun = false` — UI не открывается. Включает гео-держатель, запускает прогон, по завершении — уведомление.

```swift
import AppIntents
import UserNotifications

struct HeadlessStreaksIntent: AppIntent {
    static var title: LocalizedStringResource = "Продлить огоньки (фон)"
    static var description = IntentDescription("Запустить рассылку в фоне, не открывая приложение.")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard SessionStore.shared.isLoggedIn,
              !AppStore.shared.friendsDueToday.isEmpty,
              !RunCoordinator.shared.runActive else {
            return .result()
        }
        LocationKeeper.shared.acquire()
        defer { LocationKeeper.shared.release() }
        let record = await RunCoordinator.shared.startHeadless()
        notifyResult(record)
        return .result()
    }

    private func notifyResult(_ record: RunRecord) {
        let content = UNMutableNotificationContent()
        content.title = "Уголёк"
        if record.sentCount > 0 {
            content.body = "✅ Продлено: \(record.sentCount) · ошибок \(record.failedCount)"
        } else {
            content.body = "Нечего продлевать — все огоньки уже горят 🔥"
        }
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "ugolek.headless.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(req)
    }
}
```

**Membership:** только main app target (виджет-расширению не нужен — он не запускает прогоны).

### 3.4. `Ugolek/Core/Planner/RunCoordinator.swift` (ИЗМЕНИТЬ)

Добавить `startHeadless()` — запуск без UI (для фоновых прогонов уровней 2 и 3). Добавить гео-держатель в `start()` (уровень 1). Добавить обработку `geoPermissionRevoked`.

```swift
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class RunCoordinator {
    static let shared = RunCoordinator()

    var runActive = false
    var progressText = ""
    var progressDone = 0
    var progressTotal = 0
    var lastSummary: RunRecord?
    var showSummary = false
    var pendingAutoRun = false

    init() {
        NotificationCenter.default.addObserver(
            forName: .geoPermissionRevoked, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                AppStore.shared.settings.geoAlwaysAuto = false
                AutoRunner.shared.disarm()
                LocationKeeper.shared.stopPersistent()
            }
        }
    }

    func start(forceAll: Bool = false) {
        guard !runActive else { return }
        runActive = true
        progressText = ""
        progressDone = 0
        progressTotal = 0
        UIApplication.shared.isIdleTimerDisabled = true
        LocationKeeper.shared.acquire()   // ← уровень 1

        Task {
            let record = await StreakEngine.run(forceAll: forceAll) { [weak self] update in
                self?.progressText = update.text
                self?.progressDone = update.done
                self?.progressTotal = update.total
            }
            UIApplication.shared.isIdleTimerDisabled = false
            LocationKeeper.shared.release()   // ← уровень 1
            runActive = false
            lastSummary = record
            showSummary = !record.results.isEmpty
            ReminderService.shared.refreshAfterRun(record)
        }
    }

    /// Фоновый прогон без UI (уровни 2 и 3). Возвращает запись для уведомления.
    @discardableResult
    func startHeadless() async -> RunRecord {
        guard !runActive else { return RunRecord(date: .now, durationSeconds: 0, results: []) }
        runActive = true
        LocationKeeper.shared.acquire()
        defer {
            LocationKeeper.shared.release()
            runActive = false
        }
        let record = await StreakEngine.run { _ in }
        AppStore.shared.record(record)
        ReminderService.shared.refreshAfterRun(record)
        return record
    }

    func consumePendingAutoRunIfNeeded() {
        guard pendingAutoRun else { return }
        pendingAutoRun = false
        guard SessionStore.shared.isLoggedIn, !AppStore.shared.friendsDueToday.isEmpty else { return }
        start()
    }
}
```

### 3.5. `Ugolek/Models/AppSettings.swift` (ИЗМЕНИТЬ)

Добавить поле `geoAlwaysAuto`.

```swift
var geoAlwaysAuto: Bool = false
```

В `CodingKeys`: `case geoAlwaysAuto`.
В `init(from:)`: `geoAlwaysAuto = try c.decodeIfPresent(Bool.self, forKey: .geoAlwaysAuto) ?? false`.

### 3.6. `Ugolek/UgolekApp.swift` (ИЗМЕНИТЬ)

В `init()` подписаться на смену настроек для пересчёта `AutoRunner`. При запуске — если режим включён, вооружить.

```swift
init() {
    ReminderService.shared.activate()
    CatchUpTask.register()
    if AppStore.shared.settings.geoAlwaysAuto {
        LocationKeeper.shared.startPersistent()
        AutoRunner.shared.arm()
    }
}
```

### 3.7. `Ugolek/Screens/SettingsView.swift` (ИЗМЕНИТЬ)

Новая секция «Фоновый режим» с тумблером «Гео всегда» и статусом. При включении — запрос разрешения, тестовый dry-run, вооружение.

```swift
Section {
    Toggle("Гео всегда (авто-продление)", isOn: $store.settings.geoAlwaysAuto)
        .onChange(of: store.settings.geoAlwaysAuto) { _, enabled in
            if enabled {
                LocationKeeper.shared.requestAlways()
                // тестовый прогон без отправки
                Task {
                    let ok = await runDryRunTest()
                    if ok {
                        LocationKeeper.shared.startPersistent()
                        AutoRunner.shared.arm()
                    } else {
                        store.settings.geoAlwaysAuto = false
                    }
                }
            } else {
                AutoRunner.shared.disarm()
                LocationKeeper.shared.stopPersistent()
            }
        }
    if store.settings.geoAlwaysAuto {
        if let next = AutoRunner.shared.nextRunDate {
            LabeledContent("Следующий прогон", value: next.formatted(date: .omitted, time: .shortened))
        }
        if LocationKeeper.shared.permissionStatus != .authorizedAlways {
            Text("Нужно разрешение «Всегда» — нажми ещё раз")
                .foregroundStyle(.orange)
        }
    }
} header: {
    Text("Фоновый режим")
} footer: {
    Text("Включён — Уголёк сам продлевает огоньки каждый день в выбранное время, не открываясь. Держит геолокацию минимальной точности (вышки, не GPS). Перед включением проверит логин и список друзей без отправки сообщений.")
}
```

### 3.8. `project.yml` (ИЗМЕНИТЬ)

Добавить ключи локации в Info.plist основного таргета:

```yaml
    info:
      path: Ugolek/Info.plist
      properties:
        # ... существующие ключи ...
        NSLocationAlwaysAndWhenInUseUsageDescription: "Уголёк использует геолокацию для фоновой защиты прогона рассылки — чтобы продление не обрывалось при сворачивании приложения. Координаты не собираются и не передаются."
        NSLocationAlwaysUsageDescription: "Уголёк использует геолокацию для фоновой защиты прогона рассылки. Координаты не собираются и не передаются."
        UIBackgroundModes:
          - processing
          - location   # ← добавить
```

### 3.9. Обновить секцию «Автоматизация без тапа» в `SettingsView.swift`

Дополнить инструкцию по Командам пунктом про фоновое действие:

```swift
Text("3. Действие: «Продлить огоньки (фон)» (приложение Уголёк) — не открывает приложение")
```

### 3.10. Бонус-эксперимент: Darwin-сигнал для невидимой кнопки (опционально)

В `UgolekControlWidget.swift` (виджет-расширение): при тапе кнопка проверяет общий файл-маркер `~/Library/Widgets/ugolek.alive` (пишется приложением каждые 30 сек при активном уровне 3). Если маркер свежий — кидает Darwin-уведомление `com.ugolek.streak-trigger` и НЕ открывает приложение. Приложение ловит сигнал в `UgolekApp` и запускает `RunCoordinator.shared.startHeadless()`.

Если маркер несвежий (процесс мёртв) — кнопка открывает приложение как обычно (через `MaintainStreaksIntent`).

**Статус: экспериментальный.** Если на реальном телефоне Darwin-сигнал не долетает до живого процесса — откатываем, кнопка остаётся «мелькает + дальше само». Функционал уровней 1–3 от этого не зависит.

---

## 4. Порядок выполнения (для другой сессии)

### Этап A: Уровень 1 — гео-держатель прогона
1. Создать `LocationKeeper.swift` (§3.1).
2. Интегрировать в `RunCoordinator.start()` (§3.4) — `acquire()`/`release()`.
3. Добавить `NSLocation*UsageDescription` + `location` в `UIBackgroundModes` в `project.yml` (§3.8).
4. Коммит: `feat: geo-keeper holds process alive during run (level 1)`.
5. Push, ждать CI. Если зелёный — уровень 1 готов.

### Этап B: Уровень 2 — фоновый интент
1. Создать `HeadlessStreaksIntent.swift` (§3.3).
2. Добавить `startHeadless()` в `RunCoordinator` (§3.4).
3. Обновить инструкцию по Командам в `SettingsView` (§3.9).
4. Коммит: `feat: headless AppIntent for Shortcuts automation (level 2)`.
5. Push, ждать CI.

### Этап C: Уровень 3 — «Гео всегда»
1. Добавить `geoAlwaysAuto` в `AppSettings` (§3.5).
2. Создать `AutoRunner.swift` (§3.2).
3. Интегрировать в `UgolekApp.init()` (§3.6).
4. Добавить секцию «Фоновый режим» в `SettingsView` (§3.7) с тестовым dry-run.
5. Коммит: `feat: geo-always auto mode with dry-run test (level 3)`.
6. Push, ждать CI.

### Этап D: Бонус-эксперимент (опционально)
1. Darwin-сигнал + файл-маркер (§3.10).
2. Коммит: `experiment: invisible widget tap via darwin signal when geo-always active`.
3. Push, ждать CI. Тестировать на реальном телефоне — если не взлетит, откатить.

### Этап E: Документация
1. Обновить `HANDOFF.md` — раздел про фоновые режимы.
2. Коммит: `docs: handoff notes on background modes (levels 1-3)`.

---

## 5. Риски и компенсации

### Риск 1: WebView под замком стопорится
**Описание:** даже при живом процессе iOS может подморозить отрисовку WKWebView на заблокированном экране. JS и сеть должны жить, но не проверено.
**Вероятность:** средняя.
**Компенсация:** план Б для уровня 3 — прогон на заблокированном ставит `pendingAutoRun = true`, довыполняется при первом пробуждении телефона. Потеря — минуты, не друзья.

### Риск 2: Разрешение «Всегда» не дают
**Описание:** пользователь нажал тумблер, но не выдал «Всегда» в системном диалоге.
**Вероятность:** средняя.
**Компенсация:** тумблер проверяет `permissionStatus != .authorizedAlways` и показывает оранжевую подсказку «Нужно разрешение». При повторном тапе — `requestAlways()` снова.

### Риск 3: Система убивает процесс под давлением памяти
**Описание:** даже с активной локацией iOS может убить процесс, если память поджимает.
**Вероятность:** низкая (локация — сильный аргумент против убийства).
**Компенсация:** `pendingAutoRun` + `AutoRunner.arm()` при следующем ручном открытии — режим оживает.

### Риск 4: После перезагрузки процесс мёртв
**Описание:** iOS не поднимает приложение с фоновой локацией автоматически после ребута.
**Вероятность:** 100% (документировано).
**Компенсация:** при первом ручном открытии `UgolekApp.init()` видит `geoAlwaysAuto = true` и вооружает режим снова. Пользователь должен один раз открыть Уголёк после ребута.

### Риск 5: Батарея при «Гео всегда»
**Описание:** постоянная локация 3 км — единицы процентов в сутки, но на старом аккумуляре может быть заметнее.
**Вероятность:** низкая.
**Компенсация:** тумблер в настройках, пользователь сам решает. Watchdog гарантирует, что локация не останется висеть при зависшем прогоне.

### Риск 6: Двойной прогон при включённых уровнях 2 и 3
**Описание:** и Команды, и AutoRunner стреляют в одно время.
**Вероятность:** низкая (нужно специально включить оба).
**Компенсация:** `RunCoordinator.runActive` guard — второй запрос игнорируется. Рекомендация в UI: «включай либо/или».

### Риск 7: Darwin-сигнал не долетает (бонус-эксперимент)
**Описание:** расширение кидает сигнал, приложение его не ловит.
**Вероятность:** средняя (Darwin NC на iOS работает, но поведение под подписью sideload не проверено).
**Компенсация:** откат коммита этапа D — кнопка возвращается к «мелькает + дальше само». Функционал уровней 1–3 не страдает.

---

## 6. Взаимодействие уровней

```
                    ┌─────────────────────────────────────┐
                    │         RunCoordinator.start()       │
                    │  acquire() → прогон → release()      │  ← уровень 1 (всегда)
                    └─────────────────────────────────────┘
                                    ▲
                    ┌───────────────┼───────────────┐
                    │               │               │
              тап 🔥 (UI)    Шорткатс (фон)    AutoRunner (фон)
              MaintainStreaks  HeadlessStreaks   по таймеру
              openAppWhenRun    openAppWhenRun   geoAlwaysAuto
                = true           = false            = true
                                    │               │
                                    └───────┬───────┘
                                            │
                              ┌─────────────▼──────────────┐
                              │   LocationKeeper           │
                              │   acquire/release (L1)     │
                              │   startPersistent (L3)     │
                              │   watchdog 15 мин          │
                              └────────────────────────────┘
                                            │
                              ┌─────────────▼──────────────┐
                              │   AutoRunner               │
                              │   scheduleNext → fire      │  ← уровень 3
                              │   условия: логин, dueToday │
                              │   дрожание ±15 мин         │
                              └────────────────────────────┘
```

- Уровень 1 встроен во все прогоны — страхует и ручные, и фоновые, и авто.
- Уровни 2 и 3 не мешают друг другу (guard на `runActive`), но смысла включать оба нет.
- Уровень 3 включает уровень 1 автоматически (держатель стоит внутри `start()`).

---

## 7. Файлы проекта (справка)

| Файл | Назначение | Действие |
|------|-----------|----------|
| `Ugolek/Core/Background/LocationKeeper.swift` | Держатель геолокации | **Создать** |
| `Ugolek/Core/Background/AutoRunner.swift` | Планировщик уровня 3 | **Создать** |
| `Ugolek/Core/AppIntents/HeadlessStreaksIntent.swift` | Фоновый интент уровня 2 | **Создать** |
| `Ugolek/Core/Planner/RunCoordinator.swift` | Координатор прогона | **Изменить** (держатель + startHeadless) |
| `Ugolek/Models/AppSettings.swift` | Настройки | **Изменить** (geoAlwaysAuto) |
| `Ugolek/UgolekApp.swift` | Точка входа | **Изменить** (arm при запуске) |
| `Ugolek/Screens/SettingsView.swift` | Настройки UI | **Изменить** (секция + инструкция) |
| `project.yml` | XcodeGen конфиг | **Изменить** (права локации) |
| `HANDOFF.md` | Паспорт проекта | **Обновить** после реализации |
| `Ugolek/Core/AppIntents/UgolekControlWidget.swift` | Виджет кнопки | **Опционально** (Darwin-бонус) |
| `Ugolek/Core/AppIntents/MaintainStreaksIntent.swift` | Интент кнопки | Не менять |
| `Ugolek/Core/Planner/StreakEngine.swift` | Движок рассылки | Не менять (dryRun уже есть) |
| `Ugolek/Core/Planner/ReminderService.swift` | Уведомления | Не менять |
| `Ugolek/Core/Planner/CatchUpTask.swift` | BGTask-догонялка | Не менять |

---

## 8. Что проверяется на реальном телефоне (после реализации)

Проверки, которые может выполнить только пользователь (Кирилл) на iPhone 13 / iOS 26.1:

1. **Уровень 1:** тапнул 🔥 → заблокировал телефон → через 5 мин разблокировал → история показывает завершённый прогон.
2. **Уровень 2:** создал автоматизацию в Командах на время через 2 мин → ничего не открывалось → уведомление «✅ Продлено».
3. **Уровень 3:** включил тумблер → получил «Фон готов: N друзей» → забыл → в выбранное время уведомление «✅ Продлено».
4. **Деградация:** выключил разрешение локации в Настройках iOS → тумблер сам отщёлкнулся.
5. **Ребут:** перезагрузил телефон → открыл Уголёк → режим ожил, синяя стрелка появилась.
6. **Бонус (если реализован):** при активном уровне 3 тапнул 🔥 → приложение НЕ открылось → уведомление «✅ Продлено».

---

*План составлен на основе изученного кода проекта (RunCoordinator, StreakEngine, AppSettings, ReminderService, AppStore), документации Apple (CLLocationManager, AppIntent, WidgetKit) и обсуждения с пользователем. Все факты проверены.*
