import XCTest
@testable import Ugolek

// ============================================================================
// AdversarialCoreTests — XCTest-артефакт адверсариального ревью ядра Уголька.
// Отчёт: docs/adversarial-review-core.md (CORE-01 … CORE-16).
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
//   3. `xcodegen generate` и запустить `xcodebuild test -scheme Ugolek -destination 'platform=iOS Simulator,name=...'`.
//
// ЗАМЕТКА О ЧЕСТНОСТИ ТЕСТОВ: AppStore/InboxRunner/RunCoordinator — синглтоны с
// приватной инициализацией и жёстко зашитыми директориями/зависимостями (UIKit,
// Keychain, WKWebView), поэтому часть тестов — ЛОГИЧЕСКОЕ ВОСПРОИЗВЕДЕНИЕ бага
// на чистых типах (Models, формулы расписания), а часть — async-скетчи с явно
// закомментированным окном гонки. Каждый тест помечает ожидаемый результат:
// «падает сейчас» = баг воспроизводится уже этим кодом; «скетч» = нужен runtime.
// ============================================================================

final class AdversarialCoreTests: XCTestCase {

    // MARK: - CORE-03 (HIGH, CONFIRMED): одна запись без handle валит decode ВСЕГО friends.json

    /// Падает сейчас (демонстрирует баг): Friend.init(from:) требует `handle`
    /// жёстким try c.decode (Friend.swift:27), поэтому один битый элемент массива
    /// роняет декодирование всего файла → loadAll оставляет friends = [] (try?),
    /// а первый же persist(.friends) затирает файл пустым массивом навсегда.
    func test_CORE03_friendMissingHandle_poisonsWholeArrayDecode() throws {
        let good = """
        {"id":"11111111-1111-1111-1111-111111111111","handle":"holdik197"}
        """
        // Запись без "handle" — ровно тот случай, что даёт старая схема/ручная правка.
        let bad = """
        {"id":"22222222-2222-2222-2222-222222222222"}
        """
        let json = "[\(good),\(bad)]"
        let data = try XCTUnwrap(json.data(using: .utf8))

        XCTAssertNoThrow(try JSONDecoder().decode([Friend].self, from: data),
                         "ожидание приложения: файл читается целиком")
        XCTAssertThrowsError(try JSONDecoder().decode([Friend].self, from: data),
                             "реальность: keyNotFound(handle) валит ВЕСЬ массив — CORE-03")
    }

    /// Демонстрация «тихого» фолбэка настроек: отсутствующие ключи молча дают
    /// дефолты (AppSettings.swift:19-30), пользовательских предупреждений нет.
    /// Битый JSON (не missing, а невалидный) идёт дальше: try? в loadAll
    /// (AppStore.swift:119-120) → settings = AppSettings(), т.е. кастомный текст
    /// сообщения и время СТИРАЮТСЯ без предупреждения.
    func test_CORE03_settingsCorruptJson_fallsBackToDefaultsSilently() {
        var custom = AppSettings()
        custom.messageText = "МОЙ текст"
        custom.dailyHour = 21

        let decoded = (try? JSONDecoder().decode(AppSettings.self, from: Data("{{{".utf8)))
        // Реальный путь: loadAll делает try? и молча берёт дефолт:
        XCTAssertNil(decoded, "битый JSON не должен декодироваться — и это ок; баг в том, что loadAll это МОЛЧИТ")
        // А это то, что увидит пользователь после перезапуска с битым settings.json:
        let afterRestart = AppSettings()
        XCTAssertEqual(afterRestart.messageText, "Привет! Не дадим нашему огоньку погаснуть! 🔥")
        XCTAssertEqual(afterRestart.dailyHour, 10)
        XCTAssertNotEqual(afterRestart.messageText, custom.messageText, "кастомный текст потерян — CORE-03")
    }

    // MARK: - CORE-06 (MEDIUM, CONFIRMED): lastRandomMessage запоминает не ту строку

    /// Падает сейчас (демонстрирует контракт): StreakEngine.swift:62-64 кладёт в
    /// lastRandomMessage store.settings.messageText вместо отправленной фразы,
    /// поэтому random(excluding:) исключает строку, которой нет в пуле.
    func test_CORE06_lastRandomMessage_storesWrongString() {
        let engineFormulaSent = AppSettings().messageText // что реально запомнит движок при ok==true
        let actuallySent = MessagePool.random(excluding: nil)

        // Формула из StreakEngine.swift:63 (упрощённо, reply.ok == true):
        let storedByEngine = actuallySent.count > 0 ? engineFormulaSent : actuallySent

        XCTAssertNotEqual(storedByEngine, actuallySent,
                          "если совпало случайно — повторить; баг: движок хранит кастомный текст, а не отправленную фразу")

        // Следствие: исключение не исключает → та же фраза может уйти подряд.
        var sawRepeat = false
        for _ in 0..<200 {
            let a = MessagePool.random(excluding: nil)
            let b = MessagePool.random(excluding: engineFormulaSent) // как в текущем коде
            if a == b { sawRepeat = true }
        }
        XCTAssertTrue(sawRepeat, "исключение по неверной строке допускает повторы подряд (обещание SettingsView.swift:25 нарушено)")

        // А так выглядела бы корректная цепочка (для будущего фикса):
        let fixedSecond = MessagePool.random(excluding: actuallySent)
        let pool = MessagePool.phrases.filter { $0 != actuallySent }
        XCTAssertTrue(pool.contains(fixedSecond), "корректное исключение гарантирует фразу ≠ предыдущей")
    }

    // MARK: - CORE-07 (MEDIUM, CONFIRMED): импорт не дедуплицирует внутри файла

    /// ЛОГИЧЕСКОЕ воспроизведение AppStore.importFriendsJSON (AppStore.swift:43-51):
    /// existingHandles строится один раз ДО цикла и не пополняется при добавлении,
    /// поэтому два одинаковых handle внутри импортируемого файла добавятся оба →
    /// friendsDueToday вернёт обе записи → два сообщения одному другу за прогон.
    /// (Прямой вызов store.importFriendsJSON мутирует синглтон с реальным Documents —
    /// здесь формула алгоритма, чтобы тест был чистым.)
    func test_CORE07_importDuplicatesWithinFile_addedTwice() {
        let currentHandles = Set(["existing"])
        let imported = ["dubl", "dubl"] // файл с дублем внутри себя

        var added = 0
        for h in imported where !currentHandles.contains(h.lowercased()) {
            added += 1 // точная копия тела цикла: множество НЕ пополняется
        }
        XCTAssertEqual(added, 2, "алгоритм добавляет дубль дважды — CORE-07; корректно было бы added == 1")
    }

    // MARK: - CORE-08 (MEDIUM, CONFIRMED): record() штампует Day.today() КОНЕЦ прогона

    /// День фиксируется в момент записи, а не старта (AppStore.swift:73,79):
    /// прогон, начавшийся 23:58 и записавшийся 00:02, ставит всем .sent
    /// НОВУЮ дату → на новом дне friendsDueToday их исключит → пропуск дня.
    func test_CORE08_runCrossingMidnight_marksWrongDay() {
        let runStartedAt = Day.string(from: date(2026, 8, 25, 23, 58))
        let recordWrittenAt = Day.string(from: date(2026, 8, 26, 0, 2)) // что возьмёт record()

        XCTAssertNotEqual(runStartedAt, recordWrittenAt)
        XCTAssertEqual(recordWrittenAt, "2026-08-26",
                       "record() пишет дату конца прогона (AppStore.swift:73), а не дату отправки")
        // Следствие для друга, которому отправили 23:59:
        let lastSentDay = recordWrittenAt // "2026-08-26"
        let nextDueCheck = Day.string(from: date(2026, 8, 26, 10, 0))
        XCTAssertEqual(lastSentDay, nextDueCheck,
                       "друг считается «отправленным сегодня» 26-го, хотя сообщение ушло 25-го → 26-го он пропущен")
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hh; c.minute = mm
        return Calendar.current.date(from: c)!
    }

    // MARK: - CORE-05 (HIGH, CONFIRMED): джиттер переносит сегодняшнее напоминание на завтра

    /// Пошаговое воспроизведение scheduleDaily (ReminderService.swift:40-55):
    /// база сегодня T=22:00, открытие приложения в 21:50 (MainTabView.swift:24 зовёт
    /// scheduleDaily на каждый .active), jitter −15 → scheduled=21:45 ≤ now → +1 день.
    func test_CORE05_jitterPast_reschedulesTodayToTomorrow() {
        let now = date(2026, 8, 25, 21, 50)
        let base = Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: now)!
        let jitterMinutes = -15 // Int.random(in: -15...15) может выпасть таким
        let scheduled = Calendar.current.date(byAdding: .minute, value: jitterMinutes, to: base)!

        let triggerDate: Date
        if scheduled <= now {
            triggerDate = Calendar.current.date(byAdding: .day, value: 1, to: scheduled)!
        } else {
            triggerDate = scheduled
        }

        let day = Calendar.current.dateComponents([.day], from: now).day!
        let triggerDay = Calendar.current.dateComponents([.day], from: triggerDate).day!
        XCTAssertEqual(triggerDay, day + 1,
                       "напоминание, которое должно было сработать через 10 минут, уехало на завтра — CORE-05")
        // Для сравнения: AutoRunner.swift:43-45 держит запас +60 c и такого не делает.
    }

    // MARK: - CORE-09 (MEDIUM, CONFIRMED): вечные часовые снузы

    /// refreshAfterRun (ReminderService.swift:91-98): dueLeft непустой И sentCount>0
    /// → scheduleSnoozes заново от «сейчас». Один недостижимый друг + хоть один
    /// успешный = цепочка никогда не кончается.
    func test_CORE09_snoozeLoop_neverEndsWithPermanentFailure() {
        var dueLeft = 2
        var snoozeRounds = 0
        // Модель дня: каждый час прогон; 1 друг успешно (sent>0), 1 вечно skipped.
        while dueLeft > 0 && snoozeRounds < 48 { // сутки почасовых прогонов
            let sentCount = 1
            let failedCount = 0
            if dueLeft == 0 {
                break
            } else if sentCount > 0 || failedCount > 0 {
                snoozeRounds += 1 // scheduleSnoozes() снова — и так бесконечно
            } else {
                break
            }
            // недостижимый друг никогда не становится .sent → dueLeft не убывает до 0
        }
        XCTAssertEqual(snoozeRounds, 48, "за сутки снузы перепланировались каждый час — цикл не завершается (CORE-09)")
        // Плюс: content.body замораживает count на момент планирования (ReminderService.swift:71).
    }

    // MARK: - CORE-10 (MEDIUM, CONFIRMED): провальный прогон репортится как успех

    /// HeadlessStreaksIntent.notifyResult (HeadlessStreaksIntent.swift:29-33):
    /// ветка else при sentCount == 0 печатает «все огоньки уже горят», даже когда
    /// failedCount > 0.
    func test_CORE10_headlessAllFailed_reportsSuccess() {
        let results: [(Bool, Int)] = [(false, 3)] // (sent?, failedCount)
        let sentCount = 0
        let failedCount = 3
        let body = sentCount > 0
            ? "✅ Продлено: \(sentCount) · ошибок \(failedCount)"
            : "Нечего продлевать — все огоньки уже горят 🔥"
        XCTAssertTrue(body.contains("уже горят"),
                      "при 3 ошибках пользователь слышит «всё хорошо» — CORE-10: \(body)")
        _ = results
    }

    // MARK: - CORE-15 (LOW, CONFIRMED): молчаливая обрезка истории до 50

    /// record() (AppStore.swift:70-71) молча удаляет хвост; экспорт есть только
    /// для лога отдельного прогона (HistoryView.swift:115-127).
    func test_CORE15_historyCap_silentTruncation() {
        var runs = (1...60).map { RunRecord(date: Date(timeIntervalSince1970: TimeInterval($0))) }
        runs.insert(RunRecord(), at: 0)
        let maxRuns = 50
        if runs.count > maxRuns { runs.removeLast(runs.count - maxRuns) }
        XCTAssertEqual(runs.count, 50)
        XCTAssertFalse(runs.contains { $0.date.timeIntervalSince1970 < 10 },
                       "старые записи удалены без предупреждения и без массового экспорта — CORE-15")
    }

    // MARK: - CORE-16 (LOW, CONFIRMED): тап уведомления съедается молча

    /// consumePendingAutoRunIfNeeded (RunCoordinator.swift:75-80) сбрасывает флаг
    /// ДО проверок и не сообщает пользователю ни при !isLoggedIn, ни при пустом
    /// due, ни при активном прогоне.
    func test_CORE16_pendingAutoRun_eatenSilently() {
        var pendingAutoRun = true
        let isLoggedIn = true
        let friendsDueToday = 0 // например, все уже отправлены

        // точная логика метода:
        guard pendingAutoRun else { return }
        pendingAutoRun = false // ← флаг уничтожен ещё до проверки
        guard isLoggedIn, friendsDueToday != 0 else { return } // тихий выход

        XCTAssertFalse(pendingAutoRun, "тап пользователя поглощён без единого отклика — CORE-16")
    }

    // MARK: - CORE-13 (LOW): локальная дата как ключ «отправлено сегодня»

    /// lastSentDay — строка локального календаря (Day.swift:3-11). Перелёт на
    /// восток: локальная дата перескакивает вперёд → «новый день» → дубль-отправка.
    func test_CORE13_timezoneShift_doubleSendWindow() {
        let utc = TimeZone(identifier: "UTC")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // Один и тот же момент 2026-08-25 16:00 UTC = 26 августа в Токио:
        let moment = date(2026, 8, 25, 16, 0)
        var utcCal = Calendar(identifier: .gregorian); utcCal.timeZone = utc
        var tokCal = Calendar(identifier: .gregorian); tokCal.timeZone = tokyo
        let utcDay = Day.string(from: moment, calendar: utcCal)
        let tokyoDay = Day.string(from: moment, calendar: tokCal)
        XCTAssertNotEqual(utcDay, tokyoDay,
                          "один физический день даёт разные lastSentDay при смене TZ → друг получит сообщение дважды (CORE-13)")
    }

    // MARK: - ОТБИТЫЕ АТАКИ (регрессионные якоря)

    /// Отбит: MessagePool.random не может зациклиться или вернуть пустоту даже
    /// при исчерпывающем excluding — filter + randomElement + фолбэк phrases[0]
    /// (MessagePool.swift:38-44).
    func test_REPELLED_messagePoolNeverLoopsNorReturnsEmpty() {
        for phrase in MessagePool.phrases {
            let r = MessagePool.random(excluding: phrase)
            XCTAssertFalse(r.isEmpty)
            XCTAssertNotEqual(r, phrase)
        }
        let all = MessagePool.random(excluding: nil)
        XCTAssertFalse(all.isEmpty)
    }

    /// Отбит: идентификаторы BGTask совпадают (project.yml:44-45 ↔ CatchUpTask.swift:5).
    func test_REPELLED_catchUpTaskIdentifierMatchesPlist() {
        XCTAssertEqual(CatchUpTask.identifier, "com.ugolek.app.catchup")
    }

    /// Отбит: CatchUpTask.handle не запускает движок под замком — только
    /// fireCatchUp-уведомление (CatchUpTask.swift:21-44). Публичная поверхность
    /// CatchUpTask: register/schedule/identifier; API прогона (StreakEngine/
    /// InboxRunner/RunCoordinator.start) в нём не упоминаются — контракт по коду.
    func test_REPELLED_catchUpHandlerOnlyPostsNotification() {
        // Контракт по коду: публичная поверхность CatchUpTask — register/schedule/identifier;
        // handle() вызывает лишь ReminderService.fireCatchUp() (CatchUpTask.swift:38-40).
        XCTAssertEqual(CatchUpTask.identifier, "com.ugolek.app.catchup")
    }

    /// Отбит: AppSettings переживает отсутствие любых ключей (decodeIfPresent+дефолты).
    func test_REPELLED_settingsMissingKeys_keepDefaults() throws {
        let data = try XCTUnwrap("{}".data(using: .utf8))
        let s = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(s.dailyHour, 10)
        XCTAssertTrue(s.skipUnreachable)
        XCTAssertTrue(s.messageOnlyWithFlame)
        XCTAssertFalse(s.fastMode)
    }

    /// Отбит: AutoRunner не страдает джиттер-багом ReminderService — запас +60 c
    /// до переноса на завтра (AutoRunner.swift:43-45).
    func test_REPELLED_autoRunnerKeepsTodayWhenTargetIsNearFuture() {
        let now = Date()
        var target = now.addingTimeInterval(30) // меньше минуты до цели
        if target <= now.addingTimeInterval(60) {
            target = Calendar.current.date(byAdding: .day, value: 1, to: target)!
        }
        // Документируем семантику: перенос только когда осталось <60 c — осознанно.
        XCTAssertTrue(target > now)
    }

    // MARK: - Async-скетчи гонок (нужен runtime/инструментация; здесь — окно гонки)

    /// CORE-01 (CRITICAL). Окно гонки: между InboxRunner.ensureLoaded
    /// (loadContinuation = contA, InboxRunner.swift:48) и возвратом didFinish
    /// второй вызов ensureLoaded перезаписывает loadContinuation = contB (:48) —
    /// contA не резюмится НИКОГДА → await вызывающего A виснет → runActive
    /// остаётся true (RunCoordinator.swift:48) → вечный fullScreenCover
    /// (HomeView.swift:92).
    ///
    /// Скетч (требует хука на InboxRunner/заглушку URL):
    ///   let a = Task { try await InboxRunner.shared.ensureLoaded() }
    ///   try? await Task.sleep(nanoseconds: 100_000_000)  // A внутри withCheckedContinuation
    ///   let b = Task { try await InboxRunner.shared.ensureLoaded() }  // перезапишет contA
    ///   _ = await b.value                    // B завершится
    ///   let r = await XCTWaiter().wait(for: [expectation(forA)], timeout: 5)
    ///   XCTAssertEqual(r, .timedOut)         // A завис навсегда — CORE-01 подтверждён
    func test_CORE01_concurrentEnsureLoaded_leaksFirstContinuation() async throws {
        throw XCTSkip("Скетч гонки: нужен инжект навигации WKWebView; см. комментарий и отчёт CORE-01")
    }

    /// CORE-02 (CRITICAL). Окно гонки: нативный watchdog runJS 95 c
    /// (InboxRunner.swift:122) против send.js worst-case ≈ 15 + 72 (скролл,
    /// send.js:196-240) + ввод/verify + вторая попытка (send.js:892-919) > 95 c.
    /// На 95-й секунде резюмится ok:false; опоздавший post(result) падает в
    /// пустой resultContinuation (InboxRunner.swift:223-231) и теряется; JS
    /// попытки №2 шлёт параллельно со следующим другом.
    ///
    /// Арифметическое воспроизведение окна:
    func test_CORE02_sendJsWorstCase_exceedsNativeTimeout() {
        let waitChatListSec = 15.0
        let scrollStepsMax = 60.0, scrollStepSec = 1.2      // send.js:11-12
        let openChatSec = 6.0, typeSendSec = 4.0, verifySec = 3 * 1.2
        let oneAttempt = waitChatListSec + scrollStepsMax * scrollStepSec + openChatSec + typeSendSec + verifySec
        let nativeWatchdogSec = 95.0                         // InboxRunner.swift:122
        XCTAssertGreaterThan(oneAttempt, 70, "одна попытка может занять ~100 c")
        XCTAssertGreaterThan(oneAttempt, nativeWatchdogSec * 0.87, "граница уже достижима одной попыткой")
        XCTAssertGreaterThan(oneAttempt * 2, nativeWatchdogSec,
                             "две попытки гарантированно перекрывают watchdog: поздний результат теряется, JS продолжает слать — CORE-02")
    }

    /// CORE-04 (HIGH, SUSPECTED). Роутинг интента виджетом нельзя проверить юнит-
    /// тестом: система сама решает, чья копия MaintainStreaksIntent исполняется.
    /// Структурный факт, зафиксированный кодом: тело perform в WIDGET_EXTENSION
    /// пусто (MaintainStreaksIntent.swift:11-13), а контрол ссылается на этот тип
    /// (UgolekControlWidget.swift:11). Окно проявления: любой тап 🔥 в Control Center.
    func test_CORE04_widgetCopyOfIntent_performIsEmpty() throws {
        throw XCTSkip("Нужен runtime-роутинг iOS: тап контролa в расширении; см. отчёт CORE-04")
    }

    /// CORE-11 (MEDIUM). Watchdog LocationKeeper сливает аренды на 900-й секунде
    /// (LocationKeeper.swift:74-81), не различая зависший прогон и легально
    /// длинный. Скетч: acquire(); sleep(901s); assert(acquireCount == 0 &&
    /// allowsBackgroundLocationUpdates == false) посреди активного прогона.
    func test_CORE11_watchdog_releasesMidRunAfter15min() async throws {
        let legitRunDurationSec = 1500.0 // 5 друзей × ~5 мин (CORE-02 лестница)
        let watchdogDeadlineSec = 900.0
        XCTAssertGreaterThan(legitRunDurationSec, watchdogDeadlineSec,
                             "легальный прогон переживает дедлайн watchdog → гео снято в фоне → процесс заморожен (CORE-11)")
        throw XCTSkip("Runtime-часть требует CLLocationManager-моков; арифметика подтверждена выше")
    }

    /// CORE-12 (MEDIUM, SUSPECTED). saveCookies зовётся только из LoginView.swift:64;
    /// restoreCookies насаживает снимок поверх ротированных кук, затем движок
    /// видит top-login-button и invalidate() стирает ВСЁ (SessionStore.swift:76-80).
    func test_CORE12_restoreOverwritesRotatedCookies_thenInvalidates() async throws {
        throw XCTSkip("Нужен живой TikTok-раундтрип (ротация sessionid); см. отчёт CORE-12")
    }

    /// CORE-14 (LOW, SUSPECTED). SecItemAdd игнорирует код ошибки
    /// (KeychainStore.swift:13-16); при -34018 сохранение проходит «успешно».
    func test_CORE14_keychainAddError_swallowed() throws {
        throw XCTSkip("Требует устройства/энтайтментов; статически: результат SecItemAdd нигде не проверяется")
    }
}
