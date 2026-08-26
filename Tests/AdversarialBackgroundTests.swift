import XCTest
import CoreLocation
@testable import Ugolek

// ============================================================================
// AdversarialBackgroundTests — XCTest-артефакт адверсариального ревью ФОНОВОГО
// СТЕКА Уголька (LocationKeeper / AutoRunner / HeadlessStreaksIntent /
// RunCoordinator.startHeadless / секция «Фоновый режим» в SettingsView).
// Отчёт: docs/adversarial-review-background.md (BG-01 … BG-15).
//
// КАК ПОДКЛЮЧИТЬ БУДУЩИЙ TEST TARGET (сейчас его в проекте нет):
//
//   1. В project.yml добавить внутрь `targets:`:
//
//        UgolekTests:
//          type: bundle.unit-test
//          platform: iOS
//          sources:
//            - path: Tests
//          dependencies:
//            - target: Ugolek
//          settings:
//            base:
//              GENERATE_INFOPLIST_FILE: YES
//
//   2. В схему `Ugolek` (project.yml, schemes) добавить:
//
//        test:
//          targets:
//            - UgolekTests
//
//   3. `xcodegen generate` и запустить
//      `xcodebuild test -scheme Ugolek -destination 'platform=iOS Simulator,name=...'`.
//
// ЗАМЕТКА О ЧЕСТНОСТИ ТЕСТОВ: LocationKeeper (@MainActor NSObject с живым
// CLLocationManager), AutoRunner и RunCoordinator — несущие синглтоны с
// приватной инициализацией и системными зависимостями (CoreLocation, UIKit,
// WKWebView), поэтому тесты делятся на три честных сорта:
//   • «зеркало»       — дословное воспроизведение предиката/ветки из кода
//                       (файл:строка указан в каждом месте) и проверка того,
//                       что предикат даёт сломанный результат;
//   • «арифметика»    — бюджет времени реального прогона против константы
//                       сторожа 900 с;
//   • «скан исходника»— чтение файлов репозитория через #filePath (работает
//                       на симуляторных тест-ранах) и проверка конфигурации.
// Каждый тест помечает ожидаемый исход: «падает сейчас» = баг фиксируется этим
// тестом уже сегодня; «скетч» = нужна живая очередь/устройство для триггера.
// ============================================================================

final class AdversarialBackgroundTests: XCTestCase {

    // MARK: - BG-01 (CRITICAL, CONFIRMED): сторож 900 с короче легального медленного прогона

    /// Падает сейчас (арифметика). Сторож ставится ОДИН раз на весь прогон
    /// (acquire() → resetWatchdog(), LocationKeeper.swift:36-40,74-81; внутри
    /// прогона сброса нет — метод private). Худший легальный путь одного друга:
    /// до 3 попыток × 95 с runJS (InboxRunner.swift:102-112,121-131) плюс две
    /// перезагрузки страницы по 8+3 с. Старт: ensureLoaded до ~45 с
    /// (InboxRunner.swift:48-57,62-71). Паузы 2–6 c между друзьями
    /// (StreakEngine.swift:76-77). Уже 5 друзей по худшему пути пробивают
    /// 900 с — после чего drain (LocationKeeper.swift:79) глушит локацию под
    /// живым прогоном и iOS замораживает процесс на середине рассылки.
    func test_BG01_slowRunBudget_exceedsWatchdogCap() {
        let watchdogCap: TimeInterval = 900 // LocationKeeper.swift:77 (.seconds(900))

        let ensureLoadedWorst: TimeInterval = 40 + 2 + 3               // InboxRunner.swift:53,62,71
        let perFriendWorst: TimeInterval = 3 * 95 + 2 * (8 + 3)        // 3×runJS + 2×reloadPage
        let pauseMax: TimeInterval = 6                                  // StreakEngine.swift:76

        let friends = 5
        let worstBudget = ensureLoadedWorst
            + Double(friends) * perFriendWorst
            + Double(friends - 1) * pauseMax

        XCTAssertGreaterThan(worstBudget, watchdogCap,
                             "легальный прогон 5 друзей по худшему пути (\(worstBudget) c) дольше сторожа \(watchdogCap) c — BG-01")

        // И «умеренный» тормозящий TikTok (~60 с на друга с ретраями) пробивает
        // кап уже при 15 друзьях — это не экзотика, а задокументированная
        // плавающая вёрстка (HANDOFF.md, раздел DOM-фактов).
        let moderatePerFriend: TimeInterval = 60
        let moderateBreakEvenFriends = Int(ceil((watchdogCap - ensureLoadedWorst) / (moderatePerFriend + pauseMax)))
        XCTAssertLessThanOrEqual(moderateBreakEvenFriends, 15,
                                 "при ~60 с/друга достаточно \(moderateBreakEvenFriends) друзей, чтобы сторож убил прогон — BG-01")
    }

    /// Скетч: после drain счётчик аренды = 0, а прогон ещё идёт; будущий
    /// release() владельца молча no-op (guard acquireCount > 0,
    /// LocationKeeper.swift:43) — бухгалтерия навсегда разъезжается с реальностью,
    /// история не пишется (store.record только после цикла, StreakEngine.swift:87).
    func test_BG01_drainDesyncsLeaseAccounting_mirror() {
        var acquireCount = 0
        // владелец берёт аренду (RunCoordinator.start → acquire, RunCoordinator.swift:38)
        acquireCount += 1
        // …прогон живёт >900 c, сторож стреляет: while acquireCount > 0 { release() } (LocationKeeper.swift:79)
        while acquireCount > 0 { acquireCount -= 1 }
        XCTAssertTrue(acquireCount == 0, "drain обнулил чужую аренду — BG-01/BG-06")
        // прогон завершается и вызывает release() (RunCoordinator.swift:47):
        let released = { [count = acquireCount] in count > 0 } // зеркальный guard LocationKeeper.swift:43
        XCTAssertFalse(released(), "release() реального владельца — no-op: счётчик не отражает живых держателей")
    }

    // MARK: - BG-13 (CRITICAL): нет NSLocationWhenInUseUsageDescription → крэш на первом тапе тумблера

    /// Падает сейчас (конфигурация). requestAlwaysAuthorization()
    /// (SettingsView.swift:123 → LocationKeeper.swift:31-33) требует ОБА ключа:
    /// NSLocationAlwaysAndWhenInUseUsageDescription И NSLocationWhenInUseUsageDescription.
    /// В project.yml (:39-40) есть только Always-пара — первый тап тумблера
    /// «Гео всегда» терминирует приложение, геолокацию нельзя авторизовать вообще.
    func test_BG13_projectConfig_missingWhenInUseUsageKey() throws {
        // На симуляторном ране надёжно идти от исходника теста (#filePath — путь
        // на хосте, файловая система хоста доступна симуляторному раннеру):
        let here = URL(fileURLWithPath: #filePath)             // .../Tests/AdversarialBackgroundTests.swift
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent("project.yml")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("project.yml недоступен из раннера — проверить руками")
        }
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.contains("NSLocationAlwaysAndWhenInUseUsageDescription"),
                      "Always-ключ должен быть (project.yml:39)")
        XCTAssertTrue(text.contains("UIBackgroundModes"), "фон-режимы заявлены (project.yml:41)")

        // ВАЖНО: игла «NSLocationWhenInUseUsageDescription» НЕ является
        // подстрокой «NSLocationAlwaysAndWhenInUseUsageDescription» (перед
        // «WhenInUse» там стоит «And»), поэтому contains — корректная проверка.
        XCTAssertFalse(text.contains("NSLocationWhenInUseUsageDescription"),
                       "КЛЮЧА НЕТ — BG-13: requestAlwaysAuthorization уронит приложение при первом тапе тумблера")
    }

    // MARK: - BG-02 (HIGH, CONFIRMED): гонка тумблера — устаревший dry-test Task поверх выключенного состояния

    private final class ToggleMirror {
        var flag = false        // settings.geoAlwaysAuto
        var persistent = false  // LocationKeeper.persistent
        var armed = false       // AutoRunner.timer
        var notices = 0
    }

    /// Ветки дословно повторяют handleGeoToggle (SettingsView.swift:121-141).
    private enum GeoToggleSteps {
        static func userOn(_ s: ToggleMirror) { s.flag = true }
        /// onChange(false) — юзер щёлкнул выключить (SettingsView.swift:137-140)
        static func userOffHandler(_ s: ToggleMirror) { s.armed = false; s.persistent = false }
        /// success-ветка dry-test Task'а: флаг НЕ перепроверяется (SettingsView.swift:126-129)
        static func staleTaskSuccess(_ s: ToggleMirror) {
            s.persistent = true; s.armed = true; s.notices += 1
        }
        /// failure-ветка устаревшего Task'а: затирает флаг (SettingsView.swift:130-135)
        static func staleTaskFailure(_ s: ToggleMirror) { s.flag = false; s.notices += 1 }
    }

    /// Падает сейчас (зеркало веток). Сценарий A: ON → (сеть ~45 c) → OFF →
    /// поздний успех теста ⇒ persistent=true при geoAlwaysAuto=false:
    /// вечная фоновая геолокация без ведома юзера до ребута/отзыва разрешения.
    func test_BG02_staleDryTestSuccess_armsPersistentOverToggledOff() {
        let s = ToggleMirror()
        GeoToggleSteps.userOn(s)                    // task1 стартовал (dry-run в сети)
        GeoToggleSteps.userOffHandler(s)            // юзер выключил тумблер
        XCTAssertFalse(s.flag); XCTAssertFalse(s.persistent)

        GeoToggleSteps.staleTaskSuccess(s)          // task1 вернулся ok ПОЗЖЕ
        XCTAssertFalse(s.flag, "тумблер выключен")
        XCTAssertTrue(s.persistent, "BG-02: постоянная геолокация включена ПОВЕРХ выключенного режима")
        XCTAssertTrue(s.armed, "BG-02: AutoRunner вооружён при выключенном режиме")
    }

    /// Падает сейчас (зеркало веток). Сценарий B: провал СТАРОГО теста затирает
    /// свежее включение юзера и оставляет состояние «аренда включена, флаг выключен».
    func test_BG02_staleDryTestFailure_overridesFreshUserOn() {
        let s = ToggleMirror()
        GeoToggleSteps.userOn(s)                    // ON → task1
        GeoToggleSteps.userOffHandler(s)            // OFF
        GeoToggleSteps.userOn(s)                    // снова ON → task2 (flag=true)
        GeoToggleSteps.staleTaskFailure(s)          // поздний провал task1
        XCTAssertFalse(s.flag, "BG-02: решение юзера («вкл.») затёрто устаревшей задачей")
        GeoToggleSteps.staleTaskSuccess(s)          // task2 успел вернуться ok
        XCTAssertTrue(s.persistent)
        XCTAssertFalse(s.flag, "итоговое сломанное состояние: persistent=true, флаг=false")
    }

    // MARK: - BG-03 (ОТБИТО): программная запись флага повторно зовёт onChange(false), но это идемпотентно

    /// Отбит (зеркало): failure-ветка пишет flag=false (SettingsView.swift:131) →
    /// SwiftUI дергает onChange(false) → disarm()+stopPersistent() на пустом
    /// состоянии — no-op'ы (AutoRunner.swift:19-21; LocationKeeper.swift:66),
    /// уведомление не дублируется (postNotice один раз).
    func test_BG03_programmaticWrite_refiresOnChange_butIdempotent() {
        let s = ToggleMirror()
        GeoToggleSteps.staleTaskFailure(s)          // flag=false + одно уведомление
        GeoToggleSteps.userOffHandler(s)            // повторный onChange(false)
        GeoToggleSteps.userOffHandler(s)            // и даже ещё раз
        XCTAssertEqual(s.notices, 1, "уведомление ровно одно — двойного postNotice нет")
        XCTAssertFalse(s.persistent)
        XCTAssertFalse(s.armed)
    }

    // MARK: - BG-04 (HIGH, CONFIRMED): runDryTest минуя runActive — кнопка остаётся активной

    /// Падает сейчас (зеркало). Кнопка «Продлить сейчас»: disabled =
    /// !isLoggedIn || runActive (HomeView.swift:62). Dry-test зовёт
    /// StreakEngine.run напрямую (SettingsView.swift:146) и НЕ трогает runActive,
    /// сам тоже не проверяет его → оба направления гонки открыты.
    func test_BG04_dryTestBypassesRunActive_buttonStaysEnabled_mirror() {
        var coordinatorRunActive = false
        let sessionLoggedIn = true

        // «Идёт dry-test» — по коду это никак не отражается в координаторе:
        let dryTestRunning = true
        coordinatorRunActive = coordinatorRunActive || false // SettingsView.swift:146 ничего не пишет

        XCTAssertTrue(dryTestRunning && !coordinatorRunActive,
                      "BG-04: во время dry-test runActive=false")

        let manualButtonDisabled = !sessionLoggedIn || coordinatorRunActive
        XCTAssertFalse(manualButtonDisabled,
                       "BG-04: кнопку можно нажать Параллельно dry-test → два движка на InboxRunner.shared")
    }

    // MARK: - BG-05 (MEDIUM): любой статус != authorizedAlways хоронит persistent-режим

    /// Падает сейчас (зеркало предиката LocationKeeper.swift:90-94). Ответ юзера
    /// «При использовании приложения» (.authorizedWhenInUse) считается «отзывом»:
    /// режим гасится, постится geoPermissionRevoked, наблюдатель выключает флаг
    /// (RunCoordinator.swift:24-26). Апгрейд до Always становится невозможен —
    /// режим уже мёртв.
    func test_BG05_whenInUseStatus_killsPersistentMode_predicate() {
        func revokedFires(persistent: Bool, status: CLAuthorizationStatus) -> Bool {
            persistent && status != .authorizedAlways   // дословно LocationKeeper.swift:90
        }
        XCTAssertTrue(revokedFires(persistent: true, status: .authorizedWhenInUse),
                      "BG-05: WhenInUse убивает уровень 3 так же, как отзыв")
        XCTAssertTrue(revokedFires(persistent: true, status: .notDetermined))
        XCTAssertFalse(revokedFires(persistent: true, status: .authorizedAlways))
        // init-колбэк при notDetermined безвреден (направление 5, отбитая података):
        XCTAssertFalse(revokedFires(persistent: false, status: .notDetermined),
                       "делегат при инициализации с notDetermined ничего не ломает")
    }

    // MARK: - BG-06 (HIGH, CONFIRMED): вложенные acquire не стекуют защиту, drain ест чужие аренды

    private final class KeeperMirror {
        var acquireCount = 0
        var persistent = false
        var watchdogDeadline: TimeInterval?
        var isHolding: Bool { acquireCount > 0 || persistent }

        /// acquire(): счётчик + resetWatchdog, который ПЕРЕзапускает сторож
        /// (watchdog?.cancel() → новый сон 900 c, LocationKeeper.swift:75-79)
        func acquire(at now: TimeInterval) {
            acquireCount += 1
            watchdogDeadline = now + 900
        }
        func release() { guard acquireCount > 0 else { return }; acquireCount -= 1 }
        /// Тик сторожа: while self.acquireCount > 0 { self.release() } (LocationKeeper.swift:79)
        func fireWatchdogIfExpired(now: TimeInterval) {
            if let d = watchdogDeadline, now >= d {
                while acquireCount > 0 { release() }
            }
        }
    }

    /// Падает сейчас (зеркало). Уровень 2 даёт ДВЕ вложенные аренды на один
    /// прогон (HeadlessStreaksIntent.swift:19 + RunCoordinator.swift:61), но
    /// вторая лишь переносит дедлайн, а drain на 900-й+ секунде уничтожает
    /// ОБЕ — локация гаснет из-под живого прогона, последующие release()
    /// владельцев — no-op.
    func test_BG06_nestedAcquires_watchdogRestartsNotStacks_drainKillsAllLeases_mirror() {
        let k = KeeperMirror()
        k.acquire(at: 0)      // интент
        k.acquire(at: 300)    // startHeadless через 5 минут: дедлайн = 1200, НЕ 900+900
        XCTAssertEqual(k.watchdogDeadline, 1200, "защита не суммируется: последний acquire + 900")

        k.fireWatchdogIfExpired(now: 1200)
        XCTAssertEqual(k.acquireCount, 0, "BG-06: drain съел ОБЕ аренды одним махом")

        // Владельцы завершаются и честно вызывают свои release():
        k.release(); k.release()
        XCTAssertEqual(k.acquireCount, 0,
                       "BG-06: release() реальных держателей — no-op через guard :43; isHolding врёт")
        XCTAssertFalse(k.isHolding, "локация погашена, хотя прогон формально ещё жив")
    }

    // MARK: - BG-07 (MEDIUM): ребут + открытие позже цели переносит прогон на завтра

    /// Падает сейчас (зеркало scheduleNext, AutoRunner.swift:42-46).
    /// После ребута процесс оживает только при ручном открытии (UgolekApp.swift:12-15);
    /// если открылись хоть минуту позже целевого времени (+60 c буфер) —
    /// сегодняшний автопрогон тихо уезжает на завтра.
    func test_BG07_rebootOpenAfterTarget_pushesRunToTomorrow_mirror() {
        let cal = Calendar.current
        let now = cal.date(bySettingHour: 10, minute: 7, second: 0, of: Date())!
        var target = cal.date(bySettingHour: 10, minute: 0, second: 0, of: now)! // цель 10:00 ± джиттер

        // AutoRunner.swift:43-44
        if target <= now.addingTimeInterval(60) {
            target = cal.date(byAdding: .day, value: 1, to: target) ?? target
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: target)).day ?? 0
        XCTAssertEqual(days, 1, "BG-07: пропуск дня при открытии приложения всего на 7 минут позже цели")
    }

    // MARK: - BG-08 (MEDIUM): ночной автопрогон идёт через UI-start → алерт «Готово»

    /// Падает сейчас (зеркало). fireAndReschedule вызывает start() (AutoRunner.swift:64),
    /// тот ставит showSummary = !record.results.isEmpty (RunCoordinator.swift:50),
    /// а HomeView показывает .alert("Готово", ...) (HomeView.swift:99-110) — вопреки
    /// футеру «не открываясь и не спрашивая» (SettingsView.swift:60).
    /// isIdleTimerDisabled=true среди ночи (RunCoordinator.swift:37) — та же ветка.
    func test_BG08_autoRunUsesUiStart_summaryAlertPredicate_mirror() {
        func willShowSummary(results: Int) -> Bool { results != 0 } // RunCoordinator.swift:50
        XCTAssertTrue(willShowSummary(results: 3),
                      "BG-08: невидимый ночной прогон → внезапный алерт при следующем открытии")
        // Отбитая података направления 8: смерть процесса сбрасывает флаг — утечки нет;
        // вечное зависание невозможно (таймауты 40 c InboxRunner.swift:52-57 и 95 c :121-131).
    }

    // MARK: - BG-09 (MEDIUM): молчаливые guard'ы headless-интента

    /// Падает сейчас (зеркало HeadlessStreaksIntent.swift:14-18): любой guard →
    /// .result() БЕЗ уведомления. Автоматизация юзера выглядит работающей,
    /// ничего не делая (инструкция сама советует отключить «Спрашивать до запуска»,
    /// SettingsView.swift:78).
    func test_BG09_silentGuards_noNotification_mirror() {
        // Возвращает тело уведомления; nil = тихий .result()
        func performMirror(loggedIn: Bool, dueToday: Int, runActive: Bool) -> String? {
            guard loggedIn, dueToday > 0, !runActive else { return nil }
            return "итог"
        }
        XCTAssertNil(performMirror(loggedIn: false, dueToday: 5, runActive: false), "BG-09: нет логина — тишина")
        XCTAssertNil(performMirror(loggedIn: true, dueToday: 0, runActive: false), "BG-09: всё разослано — тишина")
        XCTAssertNil(performMirror(loggedIn: true, dueToday: 5, runActive: true), "BG-09: прогон занят — тишина")
    }

    // MARK: - BG-10 (HIGH, CONFIRMED): ложный рапорт «все огоньки горят» при failed>0/skipped>0

    /// Падает сейчас (зеркало HeadlessStreaksIntent.swift:29-33). Ветка else
    /// выбирается по одному sentCount>0 и утверждает «Нечего продлевать — все
    /// огоньки уже горят», хотя движок вернул неудачи/пропуски (failedRun со
    /// строкой «Нужен вход в TikTok», StreakEngine.swift:91-97).
    func test_BG10_notifyResultPredicate_zeroSentWithFailures_reportsFalseAllGood() {
        func body(sent: Int, failed: Int, skipped: Int) -> String { // дословно :29-33
            sent > 0 ? "✅ Продлено: \(sent) · ошибок \(failed)"
                     : "Нечего продлевать — все огоньки уже горят 🔥"
        }
        XCTAssertEqual(body(sent: 0, failed: 1, skipped: 0),
                       "Нечего продлевать — все огоньки уже горят 🔥",
                       "BG-10: протухшая сессия рапортуется как «всё горит»")
        XCTAssertEqual(body(sent: 0, failed: 0, skipped: 10),
                       "Нечего продлевать — все огоньки уже горят 🔥",
                       "BG-10: 10 недостижимых чатов рапортуются как «всё горит»")
    }

    // MARK: - BG-11 (ОТБИТО): невыполненный токен NotificationCenter у синглтона безвреден

    /// Отбит (зеркало): обработчик .geoPermissionRevoked (RunCoordinator.swift:24-26)
    /// идемпотентен — повторные вызовы не меняют конечное состояние и не плодят эффектов;
    /// токен не сохранён, но RunCoordinator.shared живёт век, утечки роста нет.
    func test_BG11_revokedHandler_idempotentForSingletonLifetime_mirror() {
        final class S { var flag = true; var armed = true; var persistent = true }
        let s = S()
        func revokeHandler() { s.flag = false; s.armed = false; s.persistent = false }
        revokeHandler(); revokeHandler(); revokeHandler()
        XCTAssertFalse(s.flag); XCTAssertFalse(s.armed); XCTAssertFalse(s.persistent)
        // Конечное состояние совпадает после любого числа постов — двойного вреда нет.
    }

    // MARK: - BG-12 (MEDIUM): битый settings.json молча хоронит воскрешение режима после ребута

    /// Падает сейчас. UgolekApp.init() читает AppStore.shared.settings.geoAlwaysAuto
    /// (UgolekApp.swift:12); loadAll глушит ошибку декода через try? (AppStore.swift:119-120)
    /// → дефолт false → arm() не выполняется никогда, следующий persist затирает файл.
    func test_BG12_corruptSettingsJson_geoModeLostAfterReboot() {
        let corrupt = Data("{{{ не-json".utf8)
        let decoded = try? JSONDecoder().decode(AppSettings.self, from: corrupt)
        XCTAssertNil(decoded, "битый файл не декодируется (это ок); баг — что loadAll об этом МОЛЧИТ")

        // То, с чем проснётся UgolekApp.init() после ребута:
        let resurrectedFromDefaults = AppSettings()
        XCTAssertFalse(resurrectedFromDefaults.geoAlwaysAuto,
                       "BG-12: авто-режим после ребута не воскреснет — и пользователь не узнает")
    }

    // MARK: - BG-14 (MEDIUM): цепочка geoPermissionRevoked беззвучна для пользователя

    /// Скан исходника: ни RunCoordinator.swift (наблюдатель, :20-28), ни
    /// LocationKeeper.swift (:86-96) не показывают пользователю НИЧЕГО —
    /// postNotice/UNNotification существуют только в SettingsView.
    func test_BG14_revokedChain_isSilent_sourceScan() throws {
        let here = URL(fileURLWithPath: #filePath)                 // .../Tests/AdversarialBackgroundTests.swift
        let src = here.deletingLastPathComponent()                  // .../Tests/
            .deletingLastPathComponent()                            // корень репо
            .appendingPathComponent("Ugolek/Core/Planner/RunCoordinator.swift")
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw XCTSkip("исходник недоступен из раннера — проверить глазами RunCoordinator.swift:20-28")
        }
        let text = try String(contentsOf: src, encoding: .utf8)
        XCTAssertTrue(text.contains(".geoPermissionRevoked"), "наблюдатель на месте (:20)")
        XCTAssertFalse(text.contains("UNNotification"),
                       "BG-14: в цепочке отзыва разрешения нет ни одного уведомления юзеру")
        XCTAssertFalse(text.contains("postNotice"),
                       "BG-14: режим умирает молча — юзер считает автопилот включённым")
    }

    // MARK: - BG-15 (LOW): два независимых джиттера — напоминание после автопрогона

    /// Падает сейчас (арифметика окон). ReminderService.scheduleDaily
    /// (ReminderService.swift:40-47) и AutoRunner.scheduleNext
    /// (AutoRunner.swift:35-42) бросают независимые ±15 мин, а refreshAfterRun
    /// (:91-98) чистит только снузы, не трогая ежедневное напоминание.
    func test_BG15_independentJitters_reminderCanFireAfterAutoRun_window() {
        let reminderJitterMin = -15, reminderJitterMax = 15
        let autoJitterMin = -15, autoJitterMax = 15
        let maxDivergenceMinutes = abs(max(reminderJitterMax, autoJitterMax) - min(reminderJitterMin, autoJitterMin))
        XCTAssertEqual(maxDivergenceMinutes, 30,
                       "разброс «напоминание vs автопрогон» достигает 30 минут")
        // Худший порядок: автопрогон в −15 (всё разослал), напоминание в +15 —
        // юзеру стучат «Пора продлить!» по пустому списку, тап уходит в guard
        // consumePendingAutoRunIfNeeded (RunCoordinator.swift:78) молча.
        XCTAssertGreaterThan(maxDivergenceMinutes, 0, "BG-15: окно нелепого напоминания ненулевое всегда")
    }
}
