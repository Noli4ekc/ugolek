import XCTest
import Foundation

// ============================================================================
// AdversarialHandlePlanTests — XCTest-артефакт адверсариального ревью плана
// docs/handle-verification-plan.md («надёжная доставка + пропуск уже продлённых»).
// Отчёт: docs/adversarial-review-handleplan.md (PLAN-01 … PLAN-14).
//
// КАК ПОДКЛЮЧИТЬ БУДУЩИЙ TEST TARGET (сейчас его в проекте нет — см. также
// шапку Tests/AdversarialCoreTests.swift):
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
//   3. `xcodegen generate`, затем
//      `xcodebuild test -scheme Ugolek -destination 'platform=iOS Simulator,name=...'`.
//
// ЗАМЕТКА О ЧЕСТНОСТИ: Swift-компилятора в среде ревью не было; файл не
// исполнялся. Логика JS из плана §3 (парсер времени lastMessageStatus,
// статус-машина, nudgeScroll-математика, resolveFresh, extractNickname)
// ЗЕРКАЛИРОВАНА на Swift 1:1 по тексту плана, чтобы тесты были исполнимыми
// в принципе и падали/проходили ровно там же, где упал бы сам план.
// DOM/WebView-зависимые атаки оформлены как async-скетчи с явной пометкой
// «СКЕТЧ» и закомментированным окном наблюдения. Каждый тест ссылается на
// PLAN-ID отчёта и строки план ↔ код.
//
// Маркировка ожидаемого исхода после РЕАЛИЗАЦИИ плана как написано:
//   [ДЕМО]  — тест проходит и этим доказывает дефект плана;
//   [СКЕТЧ] — сценарная фиксация окна гонки для живой проверки на телефоне.
// ============================================================================

final class AdversarialHandlePlanTests: XCTestCase {

    // =========================================================================
    // MARK: - Зеркала логики плана (§3.1 send.js), перенесены дословно
    // =========================================================================

    /// Зеркало planTimeClassification из lastMessageStatus (план:264–272).
    /// nil-эквивалент плана (`today === null` → break) передан кейсом .unknownBreak.
    private enum PlanVerdict { case today, notToday, unknownBreak }

    private func planClassifyTime(_ t: String) -> PlanVerdict {
        // план:267: /^\d{1,2}:\d{2}/.test(t.trim()) || /\d+\s*(мин|минут)/i.test(t)
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^\\d{1,2}:\\d{2}", options: .regularExpression) != nil { return .today }
        if t.range(of: "\\d+\\s*(мин|минут)", options: [.regularExpression, .caseInsensitive]) != nil { return .today }
        // план:268–270: /(\d+)\s*(ч|час)/i → h < 24 ? сегодня : не сегодня
        if let h = capturedInt(in: t, pattern: "(\\d+)\\s*(ч|час)") { return h < 24 ? .today : .notToday }
        // план:271: /вчера|дн|нед/i
        if t.range(of: "вчера|дн|нед", options: [.regularExpression, .caseInsensitive]) != nil { return .notToday }
        return .unknownBreak
    }

    private func capturedInt(in text: String, pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }

    /// Узел треда: полный textContent + результат эвристики направления (план:260–262).
    struct PlanBubble { let text: String; let detectedMine: Bool }

    private enum PlanThreadStatus: String {
        case maintainedToday, awaitingReply, mineOnly, unknown
    }

    /// Дословное зеркало lastMessageStatus (план:249–281).
    /// ВНИМАНИЕ: баг PLAN-03 воспроизведён намеренно — флаг ставится при любом
    /// вердикте, кроме break; вердикт «не сегодня» на флаги НЕ влияет (план:273–274).
    private func planLastMessageStatus(children: [PlanBubble]) -> PlanThreadStatus {
        let msgs = children.suffix(10)                       // план:252 slice(-10)
        var mineToday = false
        var theirsToday = false
        for msg in msgs.reversed() {                          // план:258 от свежих к старым
            guard planClassifyTime(msg.text) != .unknownBreak else { break } // план:273
            // план:274 — флаг при ЛЮБОМ распознанном вердикте (это и есть дефект)
            if msg.detectedMine { mineToday = true } else { theirsToday = true }
        }
        if mineToday && theirsToday { return .maintainedToday }   // план:277
        if theirsToday { return .awaitingReply }                  // план:278
        if mineToday { return .mineOnly }                         // план:279
        return .unknown                                           // план:280
    }

    /// Зеркало nudgeScroll-математики (план:217 ↔ send.js:168–178).
    /// CFG.scrollStep отсутствует в CFG (send.js:5–25) → delta === undefined → NaN.
    private func planNudgedScrollTop(current: Double, rawDelta: Double?, viewportHeight: Double) -> Double {
        let delta = rawDelta ?? Double.nan                 // undefined → NaN
        let step = min(delta, viewportHeight * 0.7)        // Math.min(undefined, x) === NaN
        var top = current
        if !step.isNaN { top += step }                     // WebKit игнорирует scrollTop = NaN
        return max(0, top)
    }

    /// Зеркало resolveFresh (send.js:342–358): conv-id → первый по никнейму → сам узел.
    private struct FakeListNode { let id: Int; let convId: String?; let nickname: String; let isConnected: Bool }

    private func planResolveFresh(candidate: FakeListNode, dom: [FakeListNode]) -> FakeListNode? {
        if let cid = candidate.convId {
            if let hit = dom.first(where: { $0.convId == cid && $0.isConnected }) { return hit }
        }
        let nick = candidate.nickname
        if !nick.isEmpty {
            if let hit = dom.first(where: { $0.isConnected && $0.nickname == nick }) { return hit }
        }
        return candidate.isConnected ? candidate : nil
    }

    /// Зеркало extractNickname из ProfileFetcher (план:482–495).
    private func planExtractNickname(from html: String) -> String? {
        guard let range = html.range(of: "\"nickname\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) else { return nil }
        let slice = html[range]
        guard let start = slice.firstIndex(of: ":"),
              let firstQuote = slice[start...].firstIndex(of: "\"") else { return nil }
        let after = slice.index(after: firstQuote)
        guard let endQuote = slice[after...].firstIndex(of: "\"") else { return nil }
        return String(slice[after..<endQuote])
    }

    /// Зеркало первой /@-ссылки панели для handleFromOpenChat (план:236–240).
    private func firstAtLinkHandle(panelHTML: String) -> String? {
        guard let r = panelHTML.range(of: "@([^/?#]+)", options: .regularExpression) else { return nil }
        let s = String(panelHTML[r])
        let idx = s.index(after: s.startIndex)
        return String(s[idx...]).lowercased()
    }

    // =========================================================================
    // MARK: - PLAN-01 (CRITICAL, CONFIRMED): CFG.scrollStep не существует
    // План:217 ↔ Код: send.js:5–25 (есть scrollStepMs:11, scrollMaxSteps:12;
    // scrollStep ОТСУТСТВУЕТ). Рабочий findAndOpenChat скроллит clientHeight*0.7
    // (send.js:239) — план заменяет это на несуществующий ключ CFG.
    // =========================================================================

    /// [ДЕМО] 61 итерация collectCandidates с CFG.scrollStep===undefined не двигает список.
    func test_PLAN01_scrollStepUndefined_freezesCollectionAfterFirstScreen() {
        var top = 0.0
        let viewportHeight = 800.0
        for _ in 0...(60) {                       // план:196: step <= CFG.scrollMaxSteps
            top = planNudgedScrollTop(current: top, rawDelta: nil, viewportHeight: viewportHeight)
        }
        XCTAssertEqual(top, 0.0, "scrollTop += NaN игнорируется: сбор кандидатов навсегда заперт на первом экране")
        // Контроль: существующий код (send.js:239) с тем же числом шагов уходит вниз.
        var workingTop = 0.0
        for _ in 0..<3 {
            workingTop = planNudgedScrollTop(current: workingTop, rawDelta: viewportHeight * 0.7, viewportHeight: viewportHeight)
        }
        XCTAssertGreaterThan(workingTop, 0.0, "старый механизм скроллил — новый (план:217) нет")
    }

    // =========================================================================
    // MARK: - PLAN-02 (CRITICAL, CONFIRMED): persist private, friends private(set)
    // План:413–414 и план:531–532 ↔ Код: AppStore.swift:8 (private(set) friends),
    // AppStore.swift:104 (private func persist). Рабочий паттерн — update()
    // (AppStore.swift:21–25, FriendsView.swift:128–134).
    // =========================================================================

    /// [ДЕМО] Зеркало публичной поверхности AppStore: операции плана невыразимы извне.
    func test_PLAN02_storeSurface_privatePersistAndFriends_planCannotCompile() {
        // Поверхность, доступная извне модуля (по модификаторам AppStore.swift).
        struct StoreSurface {
            let canReadFriends = true               // private(set) читается
            let canWriteFriendsDirectly = false     // запись store.friends[i] запрещена (AppStore.swift:8)
            let canCallPersist = false              // persist — private (AppStore.swift:104)
            let canCallUpdate = true                // update(_:) — публичный (AppStore.swift:21)
            func canPerformPlanSnippet() -> Bool { canWriteFriendsDirectly && canCallPersist }
        }
        let surface = StoreSurface()
        // Строки плана 413–414 и 531–532 требуют именно запретённых операций:
        XCTAssertFalse(surface.canWriteFriendsDirectly, "план пишет store.friends[i] напрямую — компиляция невозможна")
        XCTAssertFalse(surface.canCallPersist, "план зовёт приватный persist(.friends) — компиляция невозможна")
        XCTAssertFalse(surface.canPerformPlanSnippet(), "сниппет плана невыразим через публичный API; рабочий путь — AppStore.update(friend), который персистит сам")
    }

    // Вынесено отдельно, чтобы не прятать суть за хитростями выше:
    /// [СКЕТЧ] Идемпотентность alreadyMaintained держится только на некомпилируемых строках.
    /// Сценарий для живой проверки: прогон дважды в день; если lastSentDay не ставится
    /// на skip-пути (PLAN-02), друг остаётся в friendsDueToday (AppStore.swift:57–64) и
    /// каждый прогон заново открывает/сканирует/закрывает его чат.
    func test_PLAN02_alreadyMaintained_idempotency_dependsOnNonCompilingLines_SKETCH() async {
        // Шаги:
        // 1) Прогон 1: JS вернул detail '🔥 уже продлён сегодня' → план:412–415 должен
        //    поставить friend.lastSentDay = today.
        // 2) Прогон 2 в тот же день: friendsDueToday НЕ должен содержать друга.
        // Ожидание по коду плана: строка store.persist(.friends) не собирается
        // (private) ⇒ шаг 1 недостижим без переписывания на AppStore.update(friend).
        XCTAssertTrue(true, "СКЕТЧ: окно наблюдения описано в комментарии")
    }

    // =========================================================================
    // MARK: - PLAN-03 (CRITICAL, CONFIRMED): флаги копят историю независимо от «сегодня»
    // План:258–274 (флаг ставится при любом today !== null) ↔ описание плана:101–113
    // («было ли СЕГОДНЯ»). Разделитель «Сегодня» матчится /дн/ (план:271).
    // =========================================================================

    /// [ДЕМО] Тред «вчера писал только я»: статус maintained-today → ложный скип живого долга.
    func test_PLAN03_flagsIgnoreTodayVerdict_historyPollutesSkip() {
        // Дети контейнера, старые сверху (как в DOM):
        let children = [
            PlanBubble(text: "Как дела?\nВчера", detectedMine: true),   // моё, вчера
            PlanBubble(text: "Сегодня", detectedMine: false),           // разделитель дат
        ]
        // Оба узла имеют распознаваемый вердикт (не null) → оба ставят флаги.
        XCTAssertEqual(planClassifyTime("Сегодня"), .notToday, "/дн/ ловит «Сегодня» — разделитель классифицирован")
        let status = planLastMessageStatus(children: children)
        XCTAssertEqual(status, .maintainedToday, "mine(вчера)+theirs(разделитель)=«продлён сегодня» → SKIP друга, который ждал сообщения")
    }

    /// [ДЕМО] Абсолютное время вчерашнего сообщения считается «сегодня».
    func test_PLAN03_absoluteTimeFromYesterday_countedAsToday() {
        XCTAssertEqual(planClassifyTime("23:45"), .today, "якорь ^HH:MM не отличает вчера — вчерашняя реплика даёт флаг «сегодня»")
    }

    /// Контроль: на стерильном «чисто сегодняшнем» треде машина работает как задумано.
    func test_PLAN03_control_cleanTodayBothThread_stillWorks() {
        let children = [
            PlanBubble(text: "Спасаем огонёк!\n12:41", detectedMine: true),
            PlanBubble(text: "Нн: ага 🔥\n12:42", detectedMine: false),
        ]
        XCTAssertEqual(planLastMessageStatus(children: children), .maintainedToday)
    }

    // =========================================================================
    // MARK: - PLAN-05 (HIGH, CONFIRMED): регэкспы времени матчат текст сообщений
    // План:265–271 (t = msg.textContent целиком).
    // =========================================================================

    func test_PLAN05_timeRegex_matchesMessageBody_textVectors() {
        // Ложные «сегодня»:
        XCTAssertEqual(planClassifyTime("набери через 2 часа"), .today, "«2 часа» в тексте → today=true")
        XCTAssertEqual(planClassifyTime("зайду через 5 минут"), .today, "«5 минут» в тексте → today=true")
        XCTAssertEqual(planClassifyTime("12:41"), .today)
        // Ложные «не сегодня» (для сегодняшних сообщений):
        XCTAssertEqual(planClassifyTime("до встречи днём"), .notToday, "«днём» → /дн/")
        XCTAssertEqual(planClassifyTime("это было однажды"), .notToday, "«однажды» содержит «дн»")
        XCTAssertEqual(planClassifyTime("увидимся сегодня"), .notToday)
        XCTAssertEqual(planClassifyTime("недавно видел"), .notToday, "«недавно» → /нед/")
        // Корректные случаи (для полноты зеркала):
        XCTAssertEqual(planClassifyTime("Вчера"), .notToday)
        XCTAssertEqual(planClassifyTime("3 дн"), .notToday)
        XCTAssertEqual(planClassifyTime("2 ч"), .today)
        XCTAssertEqual(planClassifyTime("25 ч"), .notToday)
    }

    /// [ДЕМО] Переполнение окна slice(-10): единственное моё сообщение вытеснено
    /// десятью их сообщениями → 'awaiting-reply' → повторная отправка при закрытом стрике.
    func test_PLAN05_windowOverflow_tenPlusMessagesToday_mineDropped_resendSpam() {
        // Реальная правда дня: обе стороны писали → корректное решение — скип.
        var children: [PlanBubble] = [
            PlanBubble(text: "09:00 я уже написал утром", detectedMine: true),
        ]
        for i in 0..<10 {   // активная их переписка вытесняет моё сообщение из окна
            children.append(PlanBubble(text: String(format: "10:%02d ответ %d", i, i), detectedMine: false))
        }
        // Каждый узел распознаваем (^HH:MM), скан не прерывается — режет именно окно:
        XCTAssertEqual(children.count - 10, 1, "slice(-10) отбрасывает ровно самый старый узел — мой")
        let status = planLastMessageStatus(children: children)
        XCTAssertEqual(status, .awaitingReply,
                       "mineToday потерян из-за окна 10: статус «ждёт ответа» → прогон пишет снова, хотя стрик закрыт обеими сторонами")
    }

    // =========================================================================
    // MARK: - PLAN-04 (HIGH, CONFIRMED): второй call site findAndOpenChat в retry
    // План:341–351 заменяет ТОЛЬКО send.js:885; send.js:895–917 attempt-loop
    // на попытке 2 зовёт старый НЕверифицированный поиск (send.js:899).
    // =========================================================================

    /// [ДЕМО структурного зеркала] Таблица точек вызова: патч покрывает не все.
    func test_PLAN04_retryPath_bypassesVerification_callSiteTable() {
        let allCallSites: Set<String> = [
            "run():первый вызов (send.js:885)",
            "run():retry attempt>1 (send.js:899)",
        ]
        let patchedByPlan: Set<String> = [
            "run():первый вызов (send.js:885)",   // план:346
        ]
        let uncovered = allCallSites.subtracting(patchedByPlan)
        XCTAssertTrue(uncovered.contains("run():retry attempt>1 (send.js:899)"),
                      "retry открывает первого совпавшего без сверки @handle → промах не в того возвращается, ok:true скрывает его (record ставит lastSentDay)")
    }

    // =========================================================================
    // MARK: - PLAN-06 (HIGH, CONFIRMED): resolveFresh коллапсирует тёзок
    // План:303–338 ↔ Код: send.js:342–358 (фолбэк «первый по никнейму»,
    // отсутствие data-conv-id штатно — send.js:486 печатает 'нетConvId').
    // =========================================================================

    func test_PLAN06_resolveFresh_nicknameFallback_collapsesTwins() {
        let twin1 = FakeListNode(id: 1, convId: nil, nickname: "Нн", isConnected: true)
        let twin2 = FakeListNode(id: 2, convId: nil, nickname: "Нн", isConnected: true)
        let dom = [twin1, twin2]
        // Просим открыть ВТОРОГО кандидата:
        let resolved = planResolveFresh(candidate: twin2, dom: dom)
        XCTAssertEqual(resolved?.id, 1,
                       "без conv-id фолбэк по никнейму возвращает ПЕРВЫЙ узел: клик по кандидату №2 фактически открывает twin1 → верификация дважды против handle twin1 → «Друг не найден», хотя twin2 был в списке")
        XCTAssertNil(dom[1].convId, "отсутствие data-conv-id штатно (send.js:486 печатает 'нетConvId')")

        // Контроль: при наличии conv-id развязка работает (дыра именно в отсутствии атрибута).
        let a = FakeListNode(id: 1, convId: "c1", nickname: "Нн", isConnected: true)
        let b = FakeListNode(id: 2, convId: "c2", nickname: "Нн", isConnected: true)
        let fresh2 = planResolveFresh(candidate: b, dom: [a, b])
        XCTAssertEqual(fresh2?.id, 2, "conv-id спасает развязку тёзок")
    }

    // =========================================================================
    // MARK: - PLAN-07 (HIGH, SUSPECTED): null-верификация и чужая /@-ссылка
    // План:236–240 (первая a[href*='/@'] в панели), план:314–318 (null → пропуск),
    // план:587–591 (Risk1 называет это компенсацией).
    // =========================================================================

    /// [ДЕМО] Первая /@-ссылка в панели — из тела сообщения, не из шапки.
    func test_PLAN07_firstAtLinkInPanel_wins_overHeaderLink() {
        // Порядок DOM: сначала пузырь сообщения с упоминанием/шэром, потом шапка.
        let panelHTML = """
        <div class="msg">смотри видео <a href="/@mentionbot">автора</a></div>
        <div data-e2e="chat-header"><a href="/@rightguy">Нн</a></div>
        """
        XCTAssertEqual(firstAtLinkHandle(panelHTML: panelHTML), "mentionbot",
                       "querySelector берёт первую ссылку: правильный чат будет пропущен как «не тот»")
    }

    /// [СКЕТЧ] Регрессия доставки при сдвиге вёрстки.
    func test_PLAN07_nullHandleForAllCandidates_totalDeliveryRegression_SKETCH() async {
        // Окно наблюдения (реальный телефон):
        // 1) Реализовать селекторы панели плана:233–235 (ни один не встречается в текущем send.js).
        // 2) Если TikTok их не отдаёт → handleFromOpenChat()==null для ВСЕХ кандидатов.
        // 3) Прогон по 3 друзьям: ожидание ДО фикса — 3 доставки; по плану —
        //    «открыть→null→закрыть» ×кандидаты → «Друг не найден» ×3, история пустая.
        // Фиксация: до/после сравнение числа ok:true в RunRecord.results.
        XCTAssertTrue(true, "СКЕТЧ: требуется живой WebView")
    }

    // =========================================================================
    // MARK: - PLAN-08 (HIGH, CONFIRMED): бюджет 200 с и осиротевший результат
    // Код: InboxRunner.swift:46 (sendTimeout=200), :132–143 (timeout resume),
    // :234–238 (result резюмит любой pending continuation — без токена/username).
    // =========================================================================

    func test_PLAN08_scanBudget_exceeds200s_and_orphanResultCrossContamination() {
        // ПРОХОД 1 + ПРОХОД 2 (план:292–296): 61 шаг × CFG.scrollStepMs(1200 мс).
        let perPassSeconds = Double(61) * 1.2
        let twoPasses = perPassSeconds * 2
        XCTAssertGreaterThan(twoPasses, 144.0, "два прохода скролла — уже ~146 с до открытия первого кандидата")
        // Начальный waitForChatList до 15 c (send.js:137) + пара кандидатов по ~6 c:
        let realisticWorst = twoPasses + 15 + 12
        XCTAssertGreaterThan(realisticWorst, 200.0,
                             "бюджет InboxRunner.sendTimeout=200с пробит: ошибка таймаута НЕ содержит «не найден» → Part B молчит; осиротевший JS постит result позже → резюмится continuation следующего друга (InboxRunner.swift:234–238)")
    }

    // =========================================================================
    // MARK: - PLAN-09 (MEDIUM, CONFIRMED): closeChat фолбэк открывает чужой чат;
    // Risk 7 описывает несуществующий код
    // План:357–362 ↔ план:617–619.
    // =========================================================================

    func test_PLAN09_closeChatFallback_opensAnotherConversation_risk7Contradiction() {
        enum CloseAction { case clickBack, clickFirstListItem, none }
        func closeChatDecision(backButtonExists: Bool, listHasItems: Bool) -> CloseAction {
            if backButtonExists { return .clickBack }
            if listHasItems { return .clickFirstListItem }   // план:361 humanClick(items[0])
            return .none
        }
        XCTAssertEqual(closeChatDecision(backButtonExists: false, listHasItems: true), .clickFirstListItem,
                       "клик по элементу списка ОТКРЫВАЕТ беседу — противоположность цели closeChat; плюс read-receipts у постороннего")
        // Внутреннее противоречие плана: Risk 7 обещает paneState()/nav-messages.
        let planCloseChatCodeMarkers = ["dm-back", "BackButton", "waitForChatList", "items[0]", "humanClick"]
        let risk7Text = "closeChat() проверяет paneState() после попытки; если панель жива — клик по nav-messages"
        XCTAssertFalse(planCloseChatCodeMarkers.joined().contains("paneState"), "в коде closeChat (план:357–362) проверки paneState НЕТ")
        XCTAssertTrue(risk7Text.contains("paneState"), "компенсация Risk 7 (план:619) описывает реализацию, которой нет")
    }

    // =========================================================================
    // MARK: - PLAN-10 (MEDIUM, CONFIRMED): FriendsView onChange/onAppear/гонка
    // План:503–522 (fetchTimer/labelStatus не существуют) ↔ Код: FriendsView.swift:145–148
    // (только handle/label/isGroup/hasFlame), :196–203 (onAppear присваивает handle).
    // =========================================================================

    /// [ДЕМО] onAppear → программное изменение handle → onChange стартует фетч без юзера.
    func test_PLAN10_onAppearTriggersFetch_clobbersManualLabel() {
        struct EditorMirror {
            var handle = ""
            var scheduledFetchFor: String?
            mutating func onAppear(existingFriendHandle: String) {   // FriendsView.swift:198
                handle = existingFriendHandle                        // ← программный set
            }
            mutating func onChange(newValue: String) {               // план:504
                let clean = newValue.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "@", with: "")
                guard !clean.isEmpty else { return }
                scheduledFetchFor = clean                            // план:509 fetchTimer = Task
            }
        }
        var editor = EditorMirror()
        editor.onAppear(existingFriendHandle: "oldhandle")           // открыли редактор друга
        editor.onChange(newValue: editor.handle)                     // SwiftUI onChange сработал
        XCTAssertNotNil(editor.scheduledFetchFor,
                       "фетч запущен при простом открытии редактора → через ~1–10 с label будет перезаписан поверх ручной правки")
    }

    /// [СКЕТЧ] Сохранение до завершения дебаунс-фетча: label задним числом не применяется.
    func test_PLAN10_saveBeforeFetchCompletes_labelLost_SKETCH() async {
        // Окно наблюдения:
        // 1) Ввести @nnnnll67nl, через 300 мс нажать «Сохранить» (дебаунс 800 мс, план:510).
        // 2) Друг сохранён с label="" (save(), FriendsView.swift:208–222).
        // 3) Фетч завершается через ~2 с → Task пишет label в @State УЖЕ закрытого sheet.
        // Ожидание: friend.label в store остаётся "" — автоопределение потеряно молча.
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(true, "СКЕТЧ: гонка View↔Task проверяется на устройстве")
    }

    // =========================================================================
    // MARK: - PLAN-11 (MEDIUM): ProfileFetcher — первое вхождение, \uXXXX, exists=false
    // План:482–495 (extractNickname), план:442–444 + 473–475 (семантика exists).
    // =========================================================================

    func test_PLAN11_extractNickname_firstOccurrenceDecoyWins() {
        // Декоя «nickname» из блока рекомендаций стоит РАНЬШЕ целевого профиля:
        let html = #"{"recommendedUsers":[{"nickname":"Левый Аккаунт"}],"userInfo":{"user":{"nickname":"Настоящее Имя"}}}"#
        XCTAssertEqual(planExtractNickname(from: html), "Левый Аккаунт",
                       "range(of:) берёт первое вхождение во всём HTML — в label может попасть чужой ник (SUSPECTED на живом TikTok, CONFIRMED как свойство алгоритма)")
    }

    func test_PLAN11_extractNickname_unicodeEscapes_notDecoded() {
        // TikTok отдаёт ASCII-safe JSON: кириллица приходит как \uXXXX.
        let html = #""nickname":"\u041d\u043d""#
        let nick = planExtractNickname(from: html)
        XCTAssertEqual(nick, "\\u041d\\u043d",
                       "эскейпы не декодируются: в friend.label попадает литерал «\\u041d\\u043d», fuzzyMatch по нему бесполезен")
    }

    /// [ДЕМО] Матрица ветвей Part B: капча-200 → тихий no-op; 403/таймаут → ложное клеймо.
    func test_PLAN11_partB_branchMatrix_captchaSilent_403BlamesFriend() {
        enum Branch { case relabelAndRetry, markNotFound, none }
        func partB(exists: Bool, nickname: String?, currentLabel: String) -> Branch {
            if exists, let fresh = nickname, fresh != currentLabel { return .relabelAndRetry } // план:431
            if !exists { return .markNotFound }                                                // план:442
            return .none
        }
        XCTAssertEqual(partB(exists: true, nickname: "НовоеИмя", currentLabel: "Нн"), .relabelAndRetry)
        XCTAssertEqual(partB(exists: true, nickname: nil, currentLabel: "Нн"), .none,
                       "капча с HTTP 200 (exists=true, nickname=nil): ни обновления, ни пометки — тихий no-op, недокументирован")
        XCTAssertEqual(partB(exists: false, nickname: nil, currentLabel: "Нн"), .markNotFound,
                       "exists=false при таймауте/403/регион-блоке трактуется как «друг сменил юзернейм» — ложное клеймо в истории")
    }

    // =========================================================================
    // MARK: - PLAN-12 (MEDIUM): dry-run перебирает кандидатов до выхода
    // План:346 (findAndOpenVerifiedChat ДО dryRun-блока) ↔ send.js:887–891.
    // =========================================================================

    /// [СКЕТЧ] Пробный режим открывает/закрывает чужие беседы.
    func test_PLAN12_dryRun_pipelineIncludesCandidateLoop_SKETCH() async {
        // Новый pipeline по плану: collectCandidates(pass1) → collectCandidates(pass2?)
        // → [open → handleFromOpenChat → closeChat]* → Part D → (dryRun? выход : отправка).
        // Т.е. dryRun содержит полный перебор: реальные клики по чужим чатам
        // (read-receipts — SUSPECTED), о чём §5/§9 плана не упоминают.
        // Живая проверка: dry-run по другу с 3 тёзками → у скольких бесед поднялся «прочитано».
        XCTAssertTrue(true, "СКЕТЧ: эффект read-receipts виден только на живом аккаунте")
    }

    // =========================================================================
    // MARK: - PLAN-13 (LOW): строковый контракт detail + сожжённая фраза
    // План:348, план:410 ↔ StreakEngine.swift:63–66, send.js:889/907/910.
    // =========================================================================

    func test_PLAN13_detailMarker_substringContract_and_randomPhraseBurnedOnSkip() {
        func treatedAsMaintained(ok: Bool?, detail: String?) -> Bool {
            guard ok == true, let d = detail, d.contains("уже продлён сегодня") else { return false }
            return true
        }
        XCTAssertTrue(treatedAsMaintained(ok: true, detail: "🔥 уже продлён сегодня"))
        XCTAssertFalse(treatedAsMaintained(ok: true, detail: "подтверждено"))
        // Хрупкость контракта: любое перефразирование JS-строки молча ломает Part D
        // на Swift-стороне (нет типизированного поля alreadyMaintained в BridgeMessage).
        // Побочный эффект: reply.ok==true при skip → generic-ветка исключила бы фразу
        // из пула (StreakEngine.swift:63–66), хотя ничего не отправлено:
        let useRandomMessages = true
        var lastRandomMessage: String? = nil
        let outgoingMessage = "Огонёк горит!"
        let replyOK = true                                     // alreadyMaintained тоже ok:true
        if useRandomMessages, replyOK { lastRandomMessage = outgoingMessage } // фраза «сожжена» впустую
        XCTAssertEqual(lastRandomMessage, outgoingMessage, "ok:true при skip мутирует состояние пула фраз")
    }

    // =========================================================================
    // MARK: - PLAN-14 (LOW): метку нельзя снять повторным действием
    // План:530–533 (только установка) ↔ текст плана:541 и 624 («можно снять»).
    // =========================================================================

    func test_PLAN14_swipeRepeat_cannotUnsetMark() {
        let today = "2026-08-26"
        // Зеркало сниппета плана:530–533 — действие ТОЛЬКО ставит today, сброса нет.
        func swipeAction(current: String?) -> String? { today }
        var mark: String? = nil
        mark = swipeAction(current: mark)
        mark = swipeAction(current: mark)                          // «повторное действие» (план:541, 624)
        XCTAssertEqual(mark, today)
        XCTAssertNotEqual(swipeAction(current: mark), nil as String?,
                          "функция тотальна по установке и никогда не возвращает nil: снять отметку до конца дня невозможно вопреки собственному тексту компенсации Риска 8")
    }
}
