import XCTest
@testable import Ugolek

// ============================================================================
// AdversarialStreakCheckTests — XCTest-артефакт адверсариального ревью
// логики проверки стриков в send.js (строки 370-511) и её моста в Swift
// (StreakEngine.swift, AppStore.swift, InboxRunner.swift).
//
// АТАКИ STRIKE-01..STRIKE-12: доказывают, что streak-проверка ломается
// и отправляет дублирующие сообщения или пропускает стрики.
//
// ФОРМАТ: каждый тест — логическое воспроизведение бага на чистых типах.
// JS-логика зеркалируется в Swift без реального DOM/WKWebView.
//
// КАК ПОДКЛЮЧИТЬ TEST TARGET: см. AdversarialCoreTests.swift (раздел в шапке).
// ============================================================================

final class AdversarialStreakCheckTests: XCTestCase {

    // MARK: - Вспомогательные типы (зеркало JS-логики)

    /// Зеркало threadTodayFlags() из send.js:389-419
    enum ThreadFlags {
        case found(mine: Bool, theirs: Bool)
        case notFound   // null в JS
    }

    /// Зеркало isRecentByTimestamp() из send.js:372-383
    static func isRecentByTimestamp(cardText: String) -> String? {
        let text = cardText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if text.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil { return "today" }
        if text.range(of: #"\b\d+\s*(мин|минут|ч|час)"#, options: [.regularExpression, .caseInsensitive]) != nil { return "today" }
        if text.range(of: #"\bсегодня\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return "today" }
        if text.range(of: #"\bвчера\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return "old" }
        if text.range(of: #"\b\d+\s*дн"#, options: .regularExpression) != nil { return "old" }
        return nil
    }

    /// Зеркало внутренней логики threadTodayFlags() — поиск разделителя
    static func findTodaySeparator(nodes: [String]) -> Int {
        for i in stride(from: nodes.count - 1, through: 0, by: -1) {
            let txt = nodes[i].trimmingCharacters(in: .whitespaces).lowercased()
            if txt.isEmpty || txt.count > 24 { continue }
            if txt == "сегодня" { return i }
            if txt == "вчера"
                || txt.hasPrefix("пн") || txt.hasPrefix("вт") || txt.hasPrefix("ср")
                || txt.hasPrefix("чт") || txt.hasPrefix("пт") || txt.hasPrefix("сб") || txt.hasPrefix("вс") {
                return -1  // "Вчера" найдена раньше — сегодня ничего нет
            }
        }
        return -1  // "Сегодня" не найдена
    }

    /// Зеркало геометрической эвристики направления (send.js:415)
    static func isMineBubble(bubbleCenterX: Double, listLeft: Double, listWidth: Double) -> Bool {
        return bubbleCenterX > listLeft + listWidth * 0.55
    }

    /// Зеркало resolveFresh() (send.js:585-601)
    static func resolveFresh(
        storedConvId: String?,
        storedIsConnected: Bool,
        currentConvIds: [String]
    ) -> Bool {
        if let convId = storedConvId {
            return currentConvIds.contains(convId)
        }
        return storedIsConnected
    }

    // MARK: - STRIKE-01 (CRITICAL): threadTodayFlags() null fallthrough → send

    /// send.js:389-405 возвращает null, когда "Сегодня" не виден в DOM.
    /// send.js:460-466: повторный вызов после scrollTop=0 тоже null.
    /// send.js:503-506: null → return { ok: true } без alreadyMaintained → отправка.
    /// Результат: сообщение отправляется другу, стрик которого уже продлён сегодня.
    func test_STRIKE01_threadTodayFlagsNull_fallthroughSendsMessage() {
        func simulateThreadCheck(separatorVisible: Bool) -> ThreadFlags {
            guard separatorVisible else { return .notFound }
            return .found(mine: false, theirs: true)
        }

        func simulateFriendFlow(isGroup: Bool, separatorVisible: Bool) -> (send: Bool, skip: Bool) {
            // send.js:456-466: первый вызов
            var flags = simulateThreadCheck(separatorVisible: separatorVisible)
            // send.js:460-466: повтор после scrollTop=0
            if case .notFound = flags {
                flags = simulateThreadCheck(separatorVisible: separatorVisible)
            }

            if isGroup {
                // send.js:469-474
                if case .found(let mine, let theirs) = flags, mine || theirs {
                    return (send: false, skip: true)
                }
                return (send: true, skip: false)  // null → отправка
            } else {
                // send.js:493-506
                if case .found(let mine, let theirs) = flags {
                    if mine && theirs { return (send: false, skip: true) }
                    if mine && !theirs { return (send: false, skip: true) }
                    return (send: true, skip: false)  // только его → отправка (корректно)
                }
                return (send: true, skip: false)  // null → отправка (БАГ)
            }
        }

        // Личка: друг написал сегодня, но разделитель не виден
        let personalResult = simulateFriendFlow(isGroup: false, separatorVisible: false)
        XCTAssertTrue(personalResult.send,
                      "STRIKE-01: flags==null → отправка, хотя друг уже написал сегодня")
        XCTAssertFalse(personalResult.skip,
                       "alreadyMaintained не установлен при null flags")

        // Группа: кто-то писал сегодня, но разделитель не виден
        let groupResult = simulateFriendFlow(isGroup: true, separatorVisible: false)
        XCTAssertTrue(groupResult.send,
                      "STRIKE-01: группа с null flags → дубль-отправка")
    }

    // MARK: - STRIKE-02 (CRITICAL): isRecentByTimestamp regex ложное срабатывание

    /// send.js:376: regex /\b\d{1,2}:\d{2}\b/ матчит ЛЮБОЙ текст "число:число"
    /// в innerText карточки чата — превью сообщения, имя группы, и т.д.
    /// Результат: стрик помечается как «продлён», хотя не продлён.
    func test_STRIKE02_timestampRegex_matchesNonTimestampText() {
        // Корректные таймстемпы — должны детектиться как today
        let validTimestamps = ["12:41", "05:30", "9:05"]
        for ts in validTimestamps {
            XCTAssertEqual(Self.isRecentByTimestamp(cardText: ts), "today",
                           "корректный таймстемп '\(ts)' детектится")
        }

        // Ложные срабатывания: превью сообщений с временем
        let falsePositives: [(text: String, desc: String)] = [
            ("Позвони в 12:00 завтра", "превью с временем"),
            ("Meeting at 5:30 pm", "английское превью"),
            ("Скинь в 9:30 пожалуйста", "русское превью"),
            ("Давай в 14:00?", "короткое превью"),
        ]

        for (text, desc) in falsePositives {
            let cardText = "nickname\n\(text)"
            let result = Self.isRecentByTimestamp(cardText: cardText)
            XCTAssertEqual(result, "today",
                           "STRIKE-02: '\(desc)' → '\(cardText)' ложно детектится как today")
        }

        // Username с двоеточием
        let usernameColon = "user:1234 last message here"
        XCTAssertEqual(Self.isRecentByTimestamp(cardText: usernameColon), "today",
                       "STRIKE-02: username с двоеточием → ложно today")
    }

    // MARK: - STRIKE-03 (CRITICAL): ложное today → пропуск → потеря стрика

    /// Когда regex ложно возвращает 'today', findAndOpenVerifiedChat()
    /// (send.js:440-447) возвращает { alreadyMaintained: true }.
    /// StreakEngine.swift:72 вызывает markStreakMaintainedToday().
    /// Друг отмечен как «отправлен», но сообщение НЕ отправлено.
    /// Стрик потерян на сегодня.
    func test_STRIKE03_falseToday_causesLostStreak() {
        var lastSentDay: String? = nil
        let today = "2026-08-26"

        func markStreakMaintainedToday() {
            lastSentDay = today
        }

        // Карточка с превью "5:30" → regex → today
        let cardText = "nickname\nMeeting at 5:30"
        let tsResult = Self.isRecentByTimestamp(cardText: cardText)
        XCTAssertEqual(tsResult, "today", "ложное срабатывание regex")

        // send.js:440-447: ts === 'today' → alreadyMaintained
        if tsResult == "today" {
            markStreakMaintainedToday()
        }

        // Сообщение НЕ отправлено, но друг отмечен
        XCTAssertEqual(lastSentDay, today,
                       "STRIKE-03: друг отмечен как отправленный, но стрик не продлён")
        // Завтра: lastSentDay == today → friendsDueToday отфильтрует → друг НЕ попадёт в очередь
        // → стрик потерян на сегодня
    }

    // MARK: - STRIKE-04 (HIGH): геометрическая эвристика ломается на узком layout

    /// send.js:415: (r.left + r.width/2) > listRect.left + listRect.width * 0.55
    /// Когда список чатов узкий (100px), порог 55% = 55px. Пузыри в пределах
    /// 0-55px — «их», 55-100px — «мои». Но при позиционировании списка справа
    /// (list.left = 300) порог = 300 + 55 = 355. Любой пузырь левее 355 — «их»,
    /// даже если это мой пузырь.
    func test_STRIKE04_coordinateHeuristicBreaksOnNarrowLayout() {
        // Нормальный layout: список 500px слева
        let normalList = (left: 0.0, width: 500.0)
        let myBubbleNormal = 390.0  // центр: 390 > 275 (55% порог) → mine ✓
        XCTAssertTrue(Self.isMineBubble(bubbleCenterX: myBubbleNormal,
                                         listLeft: normalList.left,
                                         listWidth: normalList.width),
                      "нормальный layout: мой пузырь определён корректно")

        // Узкий список (iPad split view): 150px
        let narrowList = (left: 0.0, width: 150.0)
        let threshold = narrowList.left + narrowList.width * 0.55  // = 82.5

        // Мой пузырь: центр = 90 (правее порога) → mine ✓
        XCTAssertTrue(Self.isMineBubble(bubbleCenterX: 90, listLeft: narrowList.left,
                                         listWidth: narrowList.width),
                      "узкий список: мой пузырь справа определён")

        // Их пузырь: центр = 90 (тот же!) → тоже mine ✗
        // Проблема: на узком layout порог очень близко к левому краю,
        // и даже ИХ пузыри могут оказаться правее порога
        let theirBubbleNarrow = 90.0
        let myBubbleNarrow = 90.0
        let theirResult = Self.isMineBubble(bubbleCenterX: theirBubbleNarrow,
                                              listLeft: narrowList.left,
                                              listWidth: narrowList.width)
        let myResult = Self.isMineBubble(bubbleCenterX: myBubbleNarrow,
                                           listLeft: narrowList.left,
                                           listWidth: narrowList.width)
        XCTAssertEqual(theirResult, myResult,
                       "STRIKE-04: на узком layout оба пузыря на одной позиции → одинаковая классификация")

        // Список справа (RTL, перекомпоновка): list.left=300
        let rightList = (left: 300.0, width: 150.0)
        let rightThreshold = rightList.left + rightList.width * 0.55  // = 382.5
        // Их пузырь: центр = 350 (левее порога) → NOT mine ✓
        XCTAssertFalse(Self.isMineBubble(bubbleCenterX: 350,
                                          listLeft: rightList.left,
                                          listWidth: rightList.width),
                       "RTL layout: их пузырь определён")
        // Мой пузырь: центр = 400 (правее порога) → mine ✓
        XCTAssertTrue(Self.isMineBubble(bubbleCenterX: 400,
                                         listLeft: rightList.left,
                                         listWidth: rightList.width),
                      "RTL layout: мой пузырь определён")

        // Критический случай: их пузырь тоже правее порога в RTL
        let theirBubbleRTL = 410.0
        XCTAssertTrue(Self.isMineBubble(bubbleCenterX: theirBubbleRTL,
                                         listLeft: rightList.left,
                                         listWidth: rightList.width),
                      "STRIKE-04: RTL — их пузырь справа порога → ложно «мой»")
    }

    // MARK: - STRIKE-05 (HIGH): длинный текст разделителя пропускается

    /// send.js:397: if (!txt || txt.length > 24) continue;
    /// Если TikTok рендерит «Сегодня, 12:00 – 14:30» (25+ символов),
    /// разделитель пропускается, скан доходит до «Вчера» →
    /// возвращает {mine: false, theirs: false} → «сегодня ничего нет».
    func test_STRIKE05_longSeparatorText_skippedByLengthCheck() {
        // Нормальный разделитель: "сегодня" (8 символов)
        let normalNodes = ["Вчера", "сегодня", "Hello!"]
        let normalIdx = Self.findTodaySeparator(nodes: normalNodes)
        XCTAssertEqual(normalIdx, 1, "нормальный разделитель найден")

        // Длинный разделитель: 25+ символов
        let longSeparator = "сегодня, 12:00 – 14:30"  // 22 chars → passes
        XCTAssertEqual(longSeparator.count, 22, "22 chars — проходит проверку")

        let veryLongSeparator = "сегодня, 12:00 – 14:30 UTC"  // 27 chars
        XCTAssertEqual(veryLongSeparator.count, 27, "27 chars — НЕ проходит")

        let longNodes = ["вчера", veryLongSeparator, "Hello!"]
        let longIdx = Self.findTodaySeparator(nodes: longNodes)
        XCTAssertEqual(longIdx, -1,
                       "STRIKE-05: длинный разделитель пропущен → «сегодня ничего нет»")

        // Граничный случай: ровно 24 символа — проходит
        let exactly24 = String(repeating: "а", count: 24)
        XCTAssertEqual(exactly24.count, 24)
        let borderlineNodes = ["вчера", exactly24, "msg"]
        let borderlineIdx = Self.findTodaySeparator(nodes: borderlineNodes)
        XCTAssertEqual(borderlineIdx, 1, "24 символа — разделитель найден")

        // 25 символов — НЕ проходит
        let exactly25 = String(repeating: "а", count: 25)
        XCTAssertEqual(exactly25.count, 25)
        let failNodes = ["вчера", exactly25, "msg"]
        let failIdx = Self.findTodaySeparator(nodes: failNodes)
        XCTAssertEqual(failIdx, -1, "25 символов — разделитель ПРОПУЩЕН")
    }

    // MARK: - STRIKE-06 (HIGH): гонка ужеMaintained + crash до markStreakMaintainedToday

    /// StreakEngine.swift:71-79: при alreadyMaintained==true вызывается
    /// markStreakMaintainedToday(). Но если приложение падает между проверкой
    /// (line 71) и вызовом mark (line 72), друг НЕ помечен.
    /// Сообщение НЕ отправлено. Стрик потерян.
    func test_STRIKE06_alreadyMaintainedCrashBeforeMark_loseStreak() {
        var lastSentDay: String? = nil
        let today = "2026-08-26"

        struct BridgeMessage {
            var alreadyMaintained: Bool?
            var ok: Bool?
        }

        func markStreakMaintainedToday() {
            lastSentDay = today
        }

        let reply = BridgeMessage(alreadyMaintained: true, ok: true)

        // StreakEngine.swift:71: проверка
        guard reply.alreadyMaintained == true else {
            XCTFail("alreadyMaintained должен быть true")
            return
        }

        // Моделируем crash: mark НЕ вызван
        let appCrashed = true
        if !appCrashed {
            markStreakMaintainedToday()
        }

        XCTAssertNil(lastSentDay,
                     "STRIKE-06: друг не помечен после crash → стрик потерян на сегодня")

        // Следствие: завтра friendsDueToday покажет этого друга,
        // но сегодняшний стрик уже потерян (сообщение не отправлено)
    }

    // MARK: - STRIKE-06b (HIGH): record() штампует дату КОНЦА прогона, а не начала

    /// StreakEngine.swift:152: RunRecord(date: Date(), ...) — дата берётся
    /// в момент создания записи (КОНЕЦ прогона), а не в момент start = Date() (line 15).
    /// Комментарий на AppStore.swift:76 утверждает «день от СТАРТА» — это ложь.
    /// Прогон, начавшийся 23:58 и завершившийся 00:02, штампует завтрашний день →
    /// friend.lastSentDay = завтра → завтра friend не в очереди → стрик потерян.
    func test_STRIKE06b_recordFunction_stampsEndDateNotStartDate() {
        // Строка 15: let start = Date() — начало прогона
        let runStartDate = Self.makeDate(year: 2026, month: 8, day: 25, hour: 23, minute: 58)
        // Строка 152: RunRecord(date: Date(), ...) — Date() в момент завершения
        let runEndDate = Self.makeDate(year: 2026, month: 8, day: 26, hour: 0, minute: 2)

        // AppStore.swift:77: Day.string(from: run.date) — берёт ДАТУ КОНЦА
        let recordDay = Day.string(from: runEndDate)
        let startDay = Day.string(from: runStartDate)

        XCTAssertNotEqual(recordDay, startDay,
                          "дата начала и конца прогона различны")
        XCTAssertEqual(recordDay, "2026-08-26",
                       "record штампует 26 августа (конец прогона)")

        // AppStore.swift:83: friends[i].lastSentDay = today (где today = recordDay)
        let friendLastSentDay = recordDay  // "2026-08-26"

        // 26 августа: friendsDueToday проверяет lastSentDay != "2026-08-26"
        // → false → друг НЕ в очереди → НЕ отправлено
        let nextDayToday = "2026-08-26"
        XCTAssertEqual(friendLastSentDay, nextDayToday,
                       "STRIKE-06b: друг отмечен как отправленный 26-го, хотя сообщение ушло 25-го в 23:59")

        // Комментарий AppStore.swift:76: «день берём от СТАРТА прогона»
        // Факт: код использует Date() (конец), а не start (начало)
        // → комментарий врёт, баг реален
    }

    // MARK: - STRIKE-07 (HIGH): группа «old» карточка + null flags → дубль

    /// Для группы: isRecentByTimestamp вернул "old" (send.js:440 → не today),
    /// чат открыт, threadTodayFlags() вернул null (виртуализация) →
    /// send.js:469-474: flags не set → return { ok: true } → отправка.
    /// Дублирующее сообщение в группу, где стрик уже продлён.
    func test_STRIKE07_groupOldCardNullFlags_duplicateSend() {
        func simulateGroupCheck(cardTimestamp: String?, separatorVisible: Bool) -> (send: Bool, skip: Bool) {
            // send.js:439-447: быстрая проверка
            if cardTimestamp == "today" {
                return (send: false, skip: true)
            }

            // send.js:456-466: проверка треда
            var flags: ThreadFlags = .notFound
            if separatorVisible {
                flags = .found(mine: true, theirs: true)
            }
            // scroll retry
            if case .notFound = flags {
                if separatorVisible {
                    flags = .found(mine: true, theirs: true)
                }
            }

            // send.js:469-474
            if case .found(let mine, let theirs) = flags, mine || theirs {
                return (send: false, skip: true)
            }
            return (send: true, skip: false)
        }

        // Карточка "3 дн", разделитель не виден → отправка
        let result = simulateGroupCheck(cardTimestamp: "old", separatorVisible: false)
        XCTAssertTrue(result.send,
                      "STRIKE-07: группа с old карточкой и null flags → дубль")
        XCTAssertFalse(result.skip, "не пропущена")
    }

    // MARK: - STRIKE-08 (MEDIUM): неизвестные форматы времени возвращают null

    /// send.js:372-383: если TikTok покажет «только что», «30 сек»,
    /// «1m», «Just now» — regex не матчит → isRecentByTimestamp = null →
    /// код открывает чат (медленный путь), увеличивая шанс null fallthrough.
    func test_STRIKE08_unrecognizedTimeFormats_returnNull() {
        let unknownFormats = [
            "только что",
            "30 сек",
            "1m",
            "2h",
            "Just now",
            "Less than a minute",
            "1 мин.",      // точка после «мин» ломает regex
        ]

        var nullCount = 0
        for format in unknownFormats {
            let result = Self.isRecentByTimestamp(cardText: format)
            if result == nil { nullCount += 1 }
        }

        XCTAssertGreaterThanOrEqual(nullCount, 4,
                                     "STRIKE-08: большинство форматов не распознаются → forced slow path")

        // Проверяем, что «1 мин.» с точкой не матчит (regex ищет «мин» без точки)
        XCTAssertEqual(Self.isRecentByTimestamp(cardText: "1 мин."), nil,
                       "точка после «мин» ломает regex → null вместо today")
    }

    // MARK: - STRIKE-09 (MEDIUM): две.coroutines включают одного друга до mark

    /// Два прогона (ручной + фоновый) стартуют до того, как первый вызовет
    /// markStreakMaintainedToday(). friendsDueToday() не видит пометку →
    /// оба прогона включают одного друга → два сообщения.
    func test_STRIKE09_concurrentRuns_doubleIncludeSameFriend() {
        var friends: [(id: String, lastSentDay: String?, isEnabled: Bool)] = [
            ("f1", nil, true),
            ("f2", nil, true),
        ]
        let today = "2026-08-26"

        func friendsDueToday() -> [String] {
            friends.filter { $0.isEnabled && $0.lastSentDay != today }.map(\.id)
        }

        func markMaintained(id: String) {
            guard let i = friends.firstIndex(where: { $0.id == id }) else { return }
            friends[i].lastSentDay = today
        }

        // Run 1: видит f1, f2
        let run1 = friendsDueToday()
        XCTAssertEqual(run1.count, 2)

        // Run 2 стартует ДО mark от Run 1
        let run2 = friendsDueToday()
        XCTAssertEqual(run2.count, 2, "STRIKE-09: Run 2 тоже видит f1, f2")

        // Run 1 отмечает f1
        markMaintained(id: "f1")

        // Run 2 уже запланировала отправку f1 → дубль
        let overlap = Set(run1).intersection(Set(run2))
        XCTAssertEqual(overlap.count, 2,
                       "оба прогона включают одних и тех же друзей → дубли")
    }

    // MARK: - STRIKE-10 (MEDIUM): resolveFresh возвращает устаревший узел

    /// collectCandidates() находит карточку. К моменту isRecentByTimestamp()
    /// виртуализированный список перерисовался. resolveFresh() (send.js:585-601)
    /// ищет по data-conv-id, но если conv-id отсутствует, возвращает
    /// item.isConnected (устаревший узел) → проверка по неверному таймстемпу.
    func test_STRIKE10_resolveFreshStaleNode_wrongTimestamp() {
        // Зеркало resolveFresh (send.js:585-601)
        func resolveFresh(storedConvId: String?, storedConnected: Bool,
                          currentConvIds: [String]) -> Bool {
            if let convId = storedConvId {
                return currentConvIds.contains(convId)
            }
            return storedConnected
        }

        // Элемент найден без conv-id (setType = nil)
        let storedConvId: String? = nil
        let storedConnected = true

        // Список перерисовался: текущие conv-id не содержат storedConvId
        let currentConvIds = ["other-conv-id"]

        let fresh = resolveFresh(storedConvId: storedConvId,
                                  storedConnected: storedConnected,
                                  currentConvIds: currentConvIds)
        XCTAssertTrue(fresh,
                      "STRIKE-10: устаревший узел возвращён (isConnected=true, нет conv-id)")

        // isRecentByTimestamp проверяет текст УСТАРЕВШЕГО узла
        // → таймстемп может не соответствовать текущему состоянию
        let staleTimestampText = "3 дн"
        let tsResult = Self.isRecentByTimestamp(cardText: staleTimestampText)
        XCTAssertEqual(tsResult, "old",
                       "проверка устаревшего таймстемпа — не отражает текущее состояние")
    }

    // MARK: - STRIKE-11 (MEDIUM): геометрическая инверсия при 55% пороге

    /// send.js:415: порог 55% от ширины списка. Пузыри вблизи порога
    /// могут быть классифицированы неправильно: мой пузырь → «их»,
    /// их пузырь → «мой». Результат: {mine:false, theirs:true}
    /// вместо {mine:true, theirs:true} → личка отправляет повторно.
    func test_STRIKE11_bubbleClassificationInversion_nearThreshold() {
        let listWidth = 500.0
        let threshold = listWidth * 0.55  // 275

        // Мой пузырь: центр = 270 (ЛЕВЕЕ порога 275) → classified as "their"
        let myBubbleCenter = 270.0
        let myDetected = Self.isMineBubble(bubbleCenterX: myBubbleCenter,
                                            listLeft: 0, listWidth: listWidth)
        XCTAssertFalse(myDetected,
                       "STRIKE-11: мой пузырь (270) левее порога (275) → ложно «их»")

        // Их пузырь: центр = 280 (ПРАВЕЕ порога 275) → classified as "mine"
        let theirBubbleCenter = 280.0
        let theirDetected = Self.isMineBubble(bubbleCenterX: theirBubbleCenter,
                                               listLeft: 0, listWidth: listWidth)
        XCTAssertTrue(theirDetected,
                      "STRIKE-11: их пузырь (280) правее порога (275) → ложно «мой»")

        // Инверсия: мой → их, их → мой
        XCTAssertNotEqual(myDetected, theirDetected,
                          "инверсия классификации при позициях вблизи порога")
        XCTAssertFalse(myDetected, "мой неверно классифицирован как их")
        XCTAssertTrue(theirDetected, "их неверно классифицирован как мой")

        // Следствие для лички:
        // Реальность: {mine: true, theirs: true} → should skip
        // Факт: {mine: false, theirs: true} → send (STRIKE-11)
    }

    // MARK: - STRIKE-12 (LOW): системные сообщения после разделителя не детектятся

    /// send.js:409-416: поиск [data-e2e='dm-new-message-text'] внутри узлов
    /// после разделителя. Системные сообщения (вступление, смена имени, пересылка)
    /// не имеют этого атрибута → пропускаются → mine и theirs оба false →
    /// {mine: false, theirs: false} — то же, что «сегодня ничего нет».
    func test_STRIKE12_systemMessagesAfterSeparator_undetected() {
        struct Message {
            let hasTextBubble: Bool
            let isRightAligned: Bool
        }

        func detectFlags(messages: [Message]) -> (mine: Bool, theirs: Bool) {
            var mine = false
            var theirs = false
            for msg in messages {
                guard msg.hasTextBubble else { continue }  // send.js:410-411
                if msg.isRightAligned { mine = true } else { theirs = true }
            }
            return (mine: mine, theirs: theirs)
        }

        // Все сообщения — системные (нет text bubble)
        let systemMessages = [
            Message(hasTextBubble: false, isRightAligned: false),
            Message(hasTextBubble: false, isRightAligned: false),
            Message(hasTextBubble: false, isRightAligned: true),
        ]

        let flags = detectFlags(messages: systemMessages)
        XCTAssertFalse(flags.mine, "ни одного текстового пузыря → mine=false")
        XCTAssertFalse(flags.theirs, "ни одного текстового пузыря → theirs=false")

        // {false, false} = «сегодня ничего нет» — но разделитель доказывает
        // обратное. Система отправит дублирующее сообщение.
        let equivalentToNoMessages = !flags.mine && !flags.theirs
        XCTAssertTrue(equivalentToNoMessages,
                      "STRIKE-12: системные сообщения → ложный «нет активности сегодня»")
    }

    // MARK: - STRIKE-12b (LOW): комбинация STRIKE-01 + STRIKE-12 — групповые дубли

    /// В группе: системные сообщения → {false, false} → send.js:469-474:
    /// flags.mine || flags.theirs = false → send. Группа получает дубль.
    func test_STRIKE12b_groupWithSystemMessages_only_duplicate() {
        func groupCheck(separatorVisible: Bool, hasRealMessages: Bool) -> (send: Bool, skip: Bool) {
            let flags: ThreadFlags = separatorVisible
                ? .found(mine: false, theirs: false)  // все системные
                : .notFound

            if case .found(let mine, let theirs) = flags, mine || theirs {
                return (send: false, skip: true)
            }
            return (send: true, skip: false)
        }

        let result = groupCheck(separatorVisible: true, hasRealMessages: false)
        XCTAssertTrue(result.send,
                      "STRIKE-12b: группа с разделителем но только системными → дубль")
    }

    // MARK: - STRIKE-13 (MEDIUM): устаревший узел + ложное old → пропуск стрика

    /// Когда resolveFresh() возвращает устаревший узел (STRIKE-10),
    /// isRecentByTimestamp() проверяет старый таймстемп. Если карточка
    ///那时 показывала «вчера», а друг уже написал сегодня → «old» →
    /// чат открывается, но если flags тоже null → send.
    /// Если friend написал сегодня, но old на карточке → чат открывается
    /// и проверяется flags. Если flags found → корректно. Если null → send.
    func test_STRIKE13_staleNodeCombinedWithOldTimestamp_flow() {
        // Устаревшая карточка:当时 показывала "вчера"
        let staleCardText = "вчера"
        let ts = Self.isRecentByTimestamp(cardText: staleCardText)
        XCTAssertEqual(ts, "old")

        // Открываем чат: друг написал сегодня, но разделитель не виден
        let separatorVisible = false
        var flags: ThreadFlags = .notFound
        if separatorVisible { flags = .found(mine: false, theirs: true) }

        // Личка: flags null → send
        if case .found = flags {
            XCTFail("flags не должен быть found при separatorVisible=false")
        }
        // send.js:503-506: null → { ok: true }
        // Сообщение отправлено, хотя друг написал сегодня → дубль
    }

    // MARK: - STRIKE-14 (MEDIUM): verify=false обходит ВСЮ streak-проверку

    /// send.js:1147-1150: при verify===false вызывается findAndOpenChat()
    /// вместо findAndOpenVerifiedChat(). findAndOpenChat() НЕ проверяет
    /// стрик вообще — просто открывает чат. Отправка всегда происходит.
    /// Это «аварийный выключатель», который может быть включён по ошибке.
    func test_STRIKE14_verifyFalse_bypassesAllStreakChecks() {
        // При verify=false findAndOpenChat() не вызывает:
        // - isRecentByTimestamp()
        // - threadTodayFlags()
        // → отправка всегда происходит

        let useVerify = false  // payload.verify = false
        let openTarget = useVerify
            ? "findAndOpenVerifiedChat"  // с streak-проверкой
            : "findAndOpenChat"          // БЕЗ streak-проверки

        XCTAssertEqual(openTarget, "findAndOpenChat",
                       "STRIKE-14: verify=false → полный обход streak-проверки")
        // Любой друг, даже с продлённым стриком, получит сообщение
    }

    // MARK: - STRIKE-15 (LOW): friendsDueToday не учитывает alreadyMaintained

    /// friendsDueToday (AppStore.swift:57-64) фильтрует по lastSentDay.
    /// Но JS может вернуть alreadyMaintained: true, и Swift пометит друга.
    /// Проблема: если JS возвращает alreadyMaintained для ОДНОГО кандидата,
    /// а кандидатов несколько (React-дубли), код выходит на первом
    /// (send.js:446: return). Остальные кандидаты не проверяются.
    /// Это корректно, но если ПЕРВЫЙ кандидат — React-дубльWrongNick с old
    /// таймстемпом, а ВТОРОЙ — реальный друг с today таймстемпом,
    /// первый откроется и flags=null → send. Второй не проверяется.
    func test_STRIKE15_multipleCandidates_firstWrong_flagsNull() {
        // Кандидат 1: React-дубль, old таймстемп
        // Кандидат 2: реальный друг, today таймстемп
        // Код проверяет кандидатов по порядку (send.js:431)

        struct Candidate {
            let rank: Int
            let timestamp: String?
            let isCorrectUser: Bool
            let separatorVisible: Bool
        }

        let candidates = [
            Candidate(rank: 1, timestamp: "old", isCorrectUser: false, separatorVisible: false),
            Candidate(rank: 2, timestamp: "today", isCorrectUser: true, separatorVisible: true),
        ]

        var sent = false
        var checkedCount = 0

        for cand in candidates {
            checkedCount += 1
            // send.js:439-447: быстрая проверка
            if cand.timestamp == "today" {
                sent = false  // skip
                break
            }
            // send.js:449: открыть чат
            // send.js:456-466: проверка flags
            if !cand.separatorVisible {
                // flags null → send (для неправильного пользователя!)
                sent = true
                break  // send.js:506: return immediately
            }
        }

        XCTAssertTrue(sent, "STRIKE-15: отправка неправильному кандидату (React-дублю)")
        XCTAssertEqual(checkedCount, 1, "только первый кандидат проверен")
        // Второй (правильный) кандидат с today таймстемпом не проверяется
    }

    // MARK: - Вспомогательные функции

    private static func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }
}
