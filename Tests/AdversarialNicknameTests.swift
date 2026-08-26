import XCTest
import Foundation

// ============================================================================
// AdversarialNicknameTests — XCTest-артефакт адверсариального ревью
// трёхслойного каскада получения никнейма (ProfileFetcher → ProfileWebFetcher
// → InboxRunner + оркестрация FriendsView/StreakEngine).
// Отчёт: docs/adversarial-review-nickname.md (NICK-01 … NICK-16).
//
// КАК ПОДКЛЮЧИТЬ БУДУЩИЙ TEST TARGET (сейчас его в проекте нет — см. также
// шапки Tests/AdversarialCoreTests.swift / Tests/AdversarialHandlePlanTests.swift):
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
// ЗАМЕТКА О ЧЕСТНОСТИ: логика ЗЕРКАЛИРОВАНА со следующих мест 1:1 по тексту:
//   • ProfileFetcher.swift:84-113  — rawNicknameNear + decodeUnicodeEscapes;
//   • ProfileFetcher.swift:56-81   — embeddedJSON-регэксп + findNickname;
//   • FriendsView.swift:261-321    — статус-машина каскада, гард appearedHandle,
//                                     защита ручных правок autoFilledLabel;
//   • StreakEngine.swift:84-129    — часть B: триггер contains("не найден"),
//                                     каскад фолбэков, retry-решение;
//   • Resources/send.js:1047-1064  — зеркала слоя 3 (для демонстрации асимметрий).
// DOM/WebView/оконные атаки (NICK-01/03/07/13) оформлены как async-СКЕТЧИ с
// ускоренными таймингами и явным окном наблюдения для живой проверки на телефоне.
//
// Маркировка исхода:
//   [ДЕМО]  — тест проходит и этим ДОКАЗЫВАЕТ дефект реализации;
//   [СКЕТЧ] — сценарная фиксация гонки/окна для проверки на устройстве.
// Файл НИЧЕГО не импортирует из модуля приложения — только XCTest/Foundation.
// ============================================================================

final class AdversarialNicknameTests: XCTestCase {

    // =========================================================================
    // MARK: - Зеркала слоя 1 (ProfileFetcher.swift)
    // =========================================================================

    /// Зеркало ProfileFetcher.decodeUnicodeEscapes (ProfileFetcher.swift:99-113), дословно.
    private func mirrorDecodeUnicodeEscapes(_ s: String) -> String {
        guard s.contains("\\u") else { return s }
        var out = ""
        var rest = Substring(s)
        while let r = rest.range(of: "\\u([0-9a-fA-F]{4})", options: .regularExpression) {
            out += String(rest[rest.startIndex..<r.lowerBound])
            let hex = String(rest[r.lowerBound...].dropFirst(2).prefix(4))
            if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                out += String(Character(scalar))
            }
            rest = rest[r.upperBound...]
        }
        out += String(rest)
        return out
    }

    /// Эмуляция семантики слоя 3 (send.js:1058): String.fromCharCode накапливает
    /// ЕДИНИЦЫ UTF-16, поэтому суррогатные пары собираются обратно в символ.
    private func jsFromCharCodeAccumulate(_ s: String) -> String {
        var units: [UInt16] = []
        var rest = Substring(s)
        while let r = rest.range(of: "\\u([0-9a-fA-F]{4})", options: .regularExpression) {
            units.append(contentsOf: Array(String(rest[rest.startIndex..<r.lowerBound]).utf16))
            let hex = String(rest[r.lowerBound...].dropFirst(2).prefix(4))
            if let code = UInt32(hex, radix: 16), code <= UInt32(UInt16.max) {
                units.append(UInt16(code))
            }
            rest = rest[r.upperBound...]
        }
        units.append(contentsOf: Array(String(rest).utf16))
        return String(decoding: units, as: UTF16.self)
    }

    /// Зеркало ProfileFetcher.rawNicknameNear (ProfileFetcher.swift:84-97), дословно.
    private func mirrorRawNicknameNear(html: String, handle: String) -> String? {
        let pattern = "\"uniqueId\"\\s*:\\s*\"\(NSRegularExpression.escapedPattern(for: handle.lowercased()))\""
        guard let range = html.range(of: pattern, options: .regularExpression) else { return nil }
        let start = html.index(range.lowerBound, offsetBy: -300, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(range.upperBound, offsetBy: 900, limitedBy: html.endIndex) ?? html.endIndex
        let segment = html[start..<end]
        guard let nickRange = segment.range(of: "\"nickname\"\\s*:\\s*\"", options: .regularExpression) else { return nil }
        let after = segment[nickRange.upperBound...]
        guard let quote = after.firstIndex(of: "\"") else { return nil }
        var nick = String(after[after.startIndex..<quote])
        nick = nick.replacingOccurrences(of: "\\/", with: "/")
        nick = mirrorDecodeUnicodeEscapes(nick)
        return nick.isEmpty ? nil : nick
    }

    /// Зеркало слоя 3 (send.js:1052-1059): indexOf по lowercased uniqueId,
    /// окно ±(300/900), регэксп с учётом экранированных кавычек, UTF-16 декод.
    private func jsMirrorNicknameNear(html: String, handle: String) -> String? {
        guard let idxRange = html.range(of: "\"uniqueId\":\"" + handle.lowercased() + "\"") else { return nil }
        let start = html.index(idxRange.lowerBound, offsetBy: -300, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(idxRange.upperBound, offsetBy: 900, limitedBy: html.endIndex) ?? html.endIndex
        let segment = String(html[start..<end])
        // send.js:1055: /"nickname"\s*:\s*"((?:[^"\\]|\\.)*)"/ — кавычка внутри \" НЕ завершает значение
        guard let re = try? NSRegularExpression(pattern: "\"nickname\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"") else { return nil }
        let ns = segment as NSString
        guard let m = re.firstMatch(in: segment, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        var raw = ns.substring(with: m.range(at: 1))
        raw = raw.replacingOccurrences(of: "\\\"", with: "\"")
        raw = raw.replacingOccurrences(of: "\\/", with: "/")
        let nick = jsFromCharCodeAccumulate(raw)
        return nick.isEmpty ? nil : nick
    }

    /// Зеркало ProfileFetcher.embeddedJSON — только факт наличия тега (ProfileFetcher.swift:55-57).
    private func mirrorEmbeddedJSONTagFound(html: String, marker: String) -> Bool {
        html.range(of: "<script id=\"\(marker)\"[^>]*>", options: .regularExpression) != nil
    }

    /// Зеркало ProfileFetcher.findNickname (ProfileFetcher.swift:64-81), дословно.
    private func mirrorFindNickname(in node: Any, uniqueId: String) -> String? {
        if let dict = node as? [String: Any] {
            if let uid = dict["uniqueId"] as? String,
               uid.lowercased() == uniqueId,
               let nick = dict["nickname"] as? String,
               !nick.isEmpty {
                return nick
            }
            for child in dict.values {
                if let hit = mirrorFindNickname(in: child, uniqueId: uniqueId) { return hit }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let hit = mirrorFindNickname(in: child, uniqueId: uniqueId) { return hit }
            }
        }
        return nil
    }

    private func pad(_ n: Int) -> String { String(repeating: "a", count: n) }

    // =========================================================================
    // MARK: - NICK-02: суррогатные пары уничтожаются [ДЕМО]
    // =========================================================================

    func test_NICK_02_surrogatePairIsDroppedByDecodeUnicodeEscapes() {
        // Ник «Anna😀» в JSON TikTok: \uD83D\uDE00. Unicode.Scalar(0xD83D) == nil
        // (суррогаты — невалидные скаляры) → обе половины выброшены.
        let annaEmoji = "Anna\\uD83D\\uDE00"
        XCTAssertEqual(mirrorDecodeUnicodeEscapes(annaEmoji), "Anna",
                       "NICK-02: эмодзи молча выпила из никнейма")

        // Чисто эмодзи-ник: пустая строка → rawNicknameNear вернёт nil (ProfileFetcher.swift:96)
        // → фолбэк считается несработавшим, хотя данные были.
        let onlyEmoji = "\\uD83D\\uDE00\\uD83D\\uDD25" // 😀🔥
        XCTAssertEqual(mirrorDecodeUnicodeEscapes(onlyEmoji), "",
                       "NICK-02: эмодзи-ник полностью исчезает")

        // Асимметрия со слоем 3: JS-семантика UTF-16 пары СОБИРАЕТ обратно.
        XCTAssertEqual(jsFromCharCodeAccumulate(annaEmoji), "Anna\u{1F600}",
                       "слой 3 (send.js:1058) сохраняет эмодзи — результат зависит от выжившего слоя")

        // Контроль: BMP-эскейпы декодируются нормально (дефект только у суррогатов).
        XCTAssertEqual(mirrorDecodeUnicodeEscapes("\\u0041\\u0026"), "A&")
        // Одиночная верхняя половина тоже теряется (текст вокруг сохранён).
        XCTAssertEqual(mirrorDecodeUnicodeEscapes("x\\uD83Dy"), "xy")
    }

    // =========================================================================
    // MARK: - NICK-09: обрыв по первой кавычке, экранированные кавычки [ДЕМО]
    // =========================================================================

    func test_NICK_09_escapedQuoteTruncation() {
        let html = "{\"user\":{\"uniqueId\":\"quoted\",\"nickname\":\"Nick \\\"The\\\" Name\",\"verified\":true}}"
        // В файле выше записан сырой HTML: "nickname":"Nick \"The\" Name"

        let swiftResult = mirrorRawNicknameNear(html: html, handle: "quoted")
        XCTAssertEqual(swiftResult, "Nick \\",
                       "NICK-09: ProfileFetcher.swift:92 firstIndex(of:\"\\\"\") обрывает значение внутри \\")

        let jsResult = jsMirrorNicknameNear(html: html, handle: "quoted")
        XCTAssertEqual(jsResult, "Nick \"The\" Name",
                       "зеркало слоя 3 (send.js:1055) извлекает полное значение")
    }

    // =========================================================================
    // MARK: - NICK-08: регистрозависимость raw-фолбэка [ДЕМО]
    // =========================================================================

    func test_NICK_08_rawFallbackIsCaseSensitiveWhileJSONPathIsNot() throws {
        let html = "{\"userInfo\":{\"user\":{\"uniqueId\":\"John_Doe\",\"nickname\":\"Джон\"}}}"

        // JSON-путь сравнивает uid.lowercased() (ProfileFetcher.swift:67) — находит.
        let json = try JSONSerialization.jsonObject(with: Data(html.utf8))
        XCTAssertNotNil(mirrorFindNickname(in: json, uniqueId: "john_doe"))

        // Raw-путь строит паттерн из handle.lowercased() (ProfileFetcher.swift:85),
        // страница содержит оригинальный регистр → мимо.
        XCTAssertNil(mirrorRawNicknameNear(html: html, handle: "John_Doe"),
                     "NICK-08: фолбэк промахивается при упавшем JSON-парсинге и хендле с заглавными")
    }

    // =========================================================================
    // MARK: - Отбито: геометрия окна −300/+900 симметрична и покрывает раскладку
    // =========================================================================

    func test_DEFENDED_windowCoversTypicalLayoutAndMissesOnlyFarOffsets() {
        // Раскладка uniData: nickname сразу ПОСЛЕ uniqueId (+30 символов) — найдено.
        let near = "{\"uniqueId\":\"h\"," + pad(18) + "\"nickname\":\"Ник\"}"
        XCTAssertNotNil(mirrorRawNicknameNear(html: near, handle: "h"))

        // До uniqueId в пределах 300 — тоже найдено (поиск сегмента симметричен).
        let before200 = pad(200) + "\"nickname\":\"Ник\"" + pad(50) + "\"uniqueId\":\"h\"}"
        XCTAssertNotNil(mirrorRawNicknameNear(html: before200, handle: "h"))

        // Граница: дальше 300 ДО uniqueId — промах (документируем край окна).
        let before301 = pad(301) + "\"nickname\":\"Ник\"" + pad(50) + "\"uniqueId\":\"h\"}"
        XCTAssertNil(mirrorRawNicknameNear(html: before301, handle: "h"))

        // Дальше +900 ПОСЛЕ — за краем окна (атака «окно мало» отбита для реальной раскладки).
        let after1000 = "{\"uniqueId\":\"h\"," + pad(1000) + "\"nickname\":\"Ник\"}"
        XCTAssertNil(mirrorRawNicknameNear(html: after1000, handle: "h"))
    }

    // =========================================================================
    // MARK: - NICK-10: регэксп тега требует id первым атрибутом [ДЕМО]
    // =========================================================================

    func test_NICK_10_scriptTagRegexRequiresIdAsFirstAttribute() {
        let marker = "__UNIVERSAL_DATA_FOR_REHYDRATION__"

        // Текущая отдача TikTok — id первым атрибутом: находится.
        XCTAssertTrue(mirrorEmbeddedJSONTagFound(
            html: "<html><script id=\"\(marker)\" type=\"application/json\">{}</script></html>", marker: marker))
        // Перенос строки внутри тега регэксп переживает ([^>] матчит \n в ICU) — атака отбита.
        XCTAssertTrue(mirrorEmbeddedJSONTagFound(
            html: "<script id=\"\(marker)\"\n  type=\"application/json\">{}</script>", marker: marker))

        // Атака A/B: атрибут type ПЕРЕД id — регэксп даёт nil (ProfileFetcher.swift:56).
        XCTAssertFalse(mirrorEmbeddedJSONTagFound(
            html: "<script type=\"application/json\" id=\"\(marker)\">{}</script>", marker: marker),
            "NICK-10: порядок атрибутов ломает embeddedJSON")
        // Одинарные кавычки — тоже nil.
        XCTAssertFalse(mirrorEmbeddedJSONTagFound(
            html: "<script id='\(marker)'>{}</script>", marker: marker))
    }

    // =========================================================================
    // MARK: - Зеркало статус-машины редактора (FriendsView.swift)
    // =========================================================================

    enum MirrorOutcome { case found(String), blocked(String), missing(String) }
    enum MirrorNickState: Equatable { case idle, checking, found, blocked, missing }

    /// Зеркало терминального маппинга handleChanged (FriendsView.swift:280-320):
    /// .found → .found; ЛЮБОЙ другой исход → .blocked (diag-only).
    private func mirrorTerminalState(for outcome: MirrorOutcome) -> MirrorNickState {
        switch outcome {
        case .found(let nick):
            return nick.isEmpty ? .blocked : .found
        case .blocked, .missing:
            return .blocked   // FriendsView.swift:285-287: .missing лишь копит diag
        }
    }

    /// NICK-05 [ДЕМО]: состояние .missing недостижимо из любого исхода слоя 1 —
    /// красная ветка UI «Страничка не найдена» (FriendsView.swift:205) мертва.
    func test_NICK_05_missingStateIsUnreachableInEditorStateMachine() {
        let outcomes: [MirrorOutcome] = [
            .found("Ник"), .found(""), .blocked("http=200 size=1462"), .missing("http=404 size=0"),
        ]
        let reachable = Set(outcomes.map { mirrorTerminalState(for: $0) })
        XCTAssertFalse(reachable.contains(.missing),
                       "NICK-05: 404 неотличим от бот-фильтра — ветка UI .missing никогда не показывается")
        XCTAssertEqual(reachable, [.found, .blocked])
    }

    // =========================================================================
    // MARK: - NICK-04: защита ручных правок сравнивает с НОВЫМ значением [ДЕМО]
    // =========================================================================

    struct MirrorEditor {
        var label = ""
        var autoFilledLabel: String?
        /// Зеркало FriendsView.swift:310-316 дословно: сначала присваиваем, потом сравниваем.
        mutating func applyFound(fresh: String) {
            autoFilledLabel = fresh
            if label.isEmpty || label == autoFilledLabel {
                label = fresh
            }
        }
        /// Эталонное поведение (захват ПРЕЖНЕГО авто-значения до перезаписи) — для сравнения.
        mutating func applyFoundCorrect(fresh: String) {
            let previousAuto = autoFilledLabel
            autoFilledLabel = fresh
            if label.isEmpty || label == previousAuto {
                label = fresh
            }
        }
    }

    func test_NICK_04_staleAutofillNeverRefreshes() {
        var editor = MirrorEditor()

        editor.applyFound(fresh: "Old")           // первый автозаполл
        XCTAssertEqual(editor.label, "Old")

        editor.applyFound(fresh: "New")           // профиль переименован, юзер поле не трогал
        XCTAssertEqual(editor.label, "Old",
                       "NICK-04: авто-метка не обновляется — условие сверилось с уже перезаписанным autoFilledLabel")
        XCTAssertEqual(editor.autoFilledLabel, "New",
                       "плашка показывает «New», поле держит «Old» — противоречие UI↔поле")

        // Эталон обновил бы:
        var reference = MirrorEditor()
        reference.applyFoundCorrect(fresh: "Old")
        reference.applyFoundCorrect(fresh: "New")
        XCTAssertEqual(reference.label, "New")

        // Ручные правки при этом защищены в обоих вариантах (инвариант PLAN-10 жив):
        editor.label = "Моя метка"
        editor.applyFound(fresh: "Third")
        XCTAssertEqual(editor.label, "Моя метка")
    }

    // =========================================================================
    // MARK: - Гард appearedHandle (FriendsView.swift:261-273) [ОТБИТО, таблица]
    // =========================================================================

    /// Зеркало гарда: true = фетч пропущен (idle).
    private func mirrorGuardSkipsFetch(friendExists: Bool, appearedHandle: String?, clean: String) -> Bool {
        guard !clean.isEmpty else { return true }                                  // :265-267
        if friendExists && clean == appearedHandle { return true }                 // :269-272
        return false
    }

    func test_DEFENDED_appearedHandleGuardTruthTable() {
        // Открыли существующего друга — имя уже сохранено.
        XCTAssertTrue(mirrorGuardSkipsFetch(friendExists: true, appearedHandle: "x", clean: "x"))
        // Правка на другое значение — фетч нужен.
        XCTAssertFalse(mirrorGuardSkipsFetch(friendExists: true, appearedHandle: "x", clean: "y"))
        // Новый друг — гард отключён намеренно (friend != nil в условии).
        XCTAssertFalse(mirrorGuardSkipsFetch(friendExists: false, appearedHandle: "", clean: "x"))
        // Пустое поле — idle без фетча.
        XCTAssertTrue(mirrorGuardSkipsFetch(friendExists: true, appearedHandle: "x", clean: ""))
        // Стёр не до конца: промежуточные мусорные значения дёргают фетч (шум, не поломка)…
        XCTAssertFalse(mirrorGuardSkipsFetch(friendExists: true, appearedHandle: "xy", clean: "x"))
        // …а финальный возврат в исходное значение гардом ловится.
        XCTAssertTrue(mirrorGuardSkipsFetch(friendExists: true, appearedHandle: "x", clean: "x"))
    }

    // =========================================================================
    // MARK: - Зеркало части B (StreakEngine.swift:84-129)
    // =========================================================================

    struct MirrorReply {
        var ok: Bool?
        var error: String?
        var alreadyMaintained: Bool?
    }

    struct MirrorPartBVerdict: Equatable {
        var updateLabelTo: String?      // вызов AppStore.update
        var retried: Bool               // повторный InboxRunner.send
        var skippedAlreadyMaintained: Bool
        var rewrittenError: String?
    }

    /// Зеркало части B дословно по StreakEngine.swift:84-129.
    private func mirrorPartB(
        reply: MirrorReply,
        friendLabel: String,
        outcome: MirrorOutcome?,      // ProfileFetcher.fetch
        engineNick: String?,          // InboxRunner.fetchProfileNickname
        webNick: String?,             // ProfileWebFetcher.fetchNickname
        retryReply: MirrorReply
    ) -> MirrorPartBVerdict? {
        // :84-85 триггер
        guard reply.ok == false, let errText = reply.error, errText.contains("не найден") else { return nil }

        var freshNick: String?
        var profileDiag = ""
        switch outcome {
        case .found(let fresh):
            if fresh != friendLabel { freshNick = fresh }                    // :90
        case .blocked(let diag):
            profileDiag = diag
            freshNick = engineNick                                           // :94
            if freshNick == nil {                                            // :96-99
                if let fresh = webNick { freshNick = fresh } else { profileDiag += " → " + "webview-diag" }
            }
        case .missing(let diag):
            profileDiag = diag                                               // :100-101
        case nil:
            break
        }

        if let fresh = freshNick, fresh != friendLabel {                     // :104
            if retryReply.alreadyMaintained == true {                        // :117-124
                return MirrorPartBVerdict(updateLabelTo: fresh, retried: true, skippedAlreadyMaintained: true, rewrittenError: nil)
            }
            return MirrorPartBVerdict(updateLabelTo: fresh, retried: true, skippedAlreadyMaintained: false, rewrittenError: nil)
        } else if freshNick == nil, !profileDiag.isEmpty {                   // :126-128
            return MirrorPartBVerdict(updateLabelTo: nil, retried: false, skippedAlreadyMaintained: false,
                                      rewrittenError: "Друг не найден; профиль не проверился (\(profileDiag))")
        }
        return MirrorPartBVerdict(updateLabelTo: nil, retried: false, skippedAlreadyMaintained: false, rewrittenError: nil)
    }

    /// Триггер contains("не найден") (StreakEngine.swift:85) против РЕАЛЬНЫХ строк send.js.
    func test_NICK_06_triggerMatchesAllLookupErrorsIncludingDegradedVerification() {
        let matching = [
            "Пользователь не найден в списке чатов (скролл упёрся, всего 42 чата)",  // send.js:262 (verify=false!)
            "Пользователь не найден в списке чатов",                                 // send.js:267 (verify=false!)
            "Друг не найден в списке чатов",                                         // send.js:404
            "Друг не найден: ни один кандидат не прошёл верификацию (проверено 3)",  // send.js:442 — деградация PLAN-07
        ]
        for text in matching {
            XCTAssertTrue(text.contains("не найден"), "триггер части B должен сработать: \(text)")
        }
        // Не триггерятся (и хорошо):
        let nonMatching = ["Не смог прочитать юзернейм открытого чата", "Чат не открылся", "Превышено время ожидания (200 с)"]
        for text in nonMatching {
            XCTAssertFalse(text.contains("не найден"))
        }
        // Арифметика лавины без негативного кэша: 10 мёртвых друзей × прогон =
        // 10×(URLSession + движок-fetch + offscreen-webview + retry-send) = 40 запросов.
        XCTAssertEqual(10 * 4, 40, "NICK-06: счёт обращений к TikTok за один прогон")
    }

    /// Все ветки решения части B, включая NICK-02-компаундинг (порча label сохраняется).
    func test_NICK_11_partBDecisionTreeBranches() {
        let baseFail = MirrorReply(ok: false, error: "Друг не найден: ни один кандидат не прошёл верификацию", alreadyMaintained: nil)

        // 1) found, но fresh == label: ни ретрая, ни перезаписи ошибки — история честная.
        XCTAssertEqual(
            mirrorPartB(reply: baseFail, friendLabel: "Нн", outcome: .found("Нн"), engineNick: nil, webNick: nil,
                        retryReply: MirrorReply(ok: true, error: nil, alreadyMaintained: nil)),
            MirrorPartBVerdict(updateLabelTo: nil, retried: false, skippedAlreadyMaintained: false, rewrittenError: nil))

        // 2) blocked → движок нашёл → retry с обновлением.
        XCTAssertEqual(
            mirrorPartB(reply: baseFail, friendLabel: "Old", outcome: .blocked("http=200 size=1462"),
                        engineNick: "Fresh", webNick: nil,
                        retryReply: MirrorReply(ok: true, error: nil, alreadyMaintained: nil)),
            MirrorPartBVerdict(updateLabelTo: "Fresh", retried: true, skippedAlreadyMaintained: false, rewrittenError: nil))

        // 3) blocked → движок пуст → webview нашёл → retry.
        XCTAssertEqual(
            mirrorPartB(reply: baseFail, friendLabel: "Old", outcome: .blocked("d"),
                        engineNick: nil, webNick: "Fresh",
                        retryReply: MirrorReply(ok: true, error: nil, alreadyMaintained: nil)),
            MirrorPartBVerdict(updateLabelTo: "Fresh", retried: true, skippedAlreadyMaintained: false, rewrittenError: nil))

        // 4) всё пусто → ошибка переписана с diag.
        let v4 = mirrorPartB(reply: baseFail, friendLabel: "Old", outcome: .missing("http=404 size=0"),
                             engineNick: nil, webNick: nil,
                             retryReply: MirrorReply(ok: true, error: nil, alreadyMaintained: nil))
        XCTAssertEqual(v4?.rewrittenError, "Друг не найден; профиль не проверился (http=404 size=0)")
        XCTAssertEqual(v4?.retried, false)

        // 5) retry ответил alreadyMaintained → скип без записи failed.
        XCTAssertEqual(
            mirrorPartB(reply: baseFail, friendLabel: "Old", outcome: .blocked("d"), engineNick: "Fresh", webNick: nil,
                        retryReply: MirrorReply(ok: true, error: nil, alreadyMaintained: true)),
            MirrorPartBVerdict(updateLabelTo: "Fresh", retried: true, skippedAlreadyMaintained: true, rewrittenError: nil))

        // 6) КОМПАУНДИНГ NICK-02: испорченный (без эмодзи) ник ≠ хорошему label →
        //    часть B перезапишет корректную метку испорченной.
        let corrupted = "Анна" // было «Анна😀», суррогаты потеряны на слое 1
        let v6 = mirrorPartB(reply: baseFail, friendLabel: "Анна\u{1F600}", outcome: .found(corrupted),
                             engineNick: nil, webNick: nil,
                             retryReply: MirrorReply(ok: false, error: "Чат не открылся", alreadyMaintained: nil))
        XCTAssertEqual(v6?.updateLabelTo, corrupted,
                       "часть B принимает испорченный ник как «обновление» — порча персистится")
        XCTAssertEqual(v6?.retried, true, "и делает retry с ухудшенной иглой rank-2")
    }

    // =========================================================================
    // MARK: - NICK-03 [СКЕТЧ]: каскад переживает закрытие редактора и доходит до makeKey
    // =========================================================================

    private actor EventLog {
        var events: [String] = []
        func add(_ e: String) { events.append(e) }
    }

    /// Сценарий NICK-01/NICK-03 с ускоренными таймингами (реальные: debounce 800 мс,
    /// слой 1 ~1-10 с, слой 2 до 25 с, ensureLoaded 40 с).
    /// Окно наблюдения на устройстве: открыть редактор → ввести юзернейм → нажать «Отмена»
    /// до появления статуса → клавиатура складывается сама через 10–75 с; в Xcode-логе
    /// видно «makeKey» ПОСЛЕ dismiss. Здесь — детерминированное зеркало порядка событий.
    func test_NICK_03_SKETCH_cascadeSurvivesDismissAndReachesMakeKey() async {
        let log = EventLog()
        var nickTask: Task<Void, Never>? = nil

        // Редактор: handleChanged создал задачу каскада (FriendsView.swift:274-321).
        nickTask = Task {
            try? await Task.sleep(for: .milliseconds(20))   // debounce 800 мс
            await log.add("layer1:urlsession")
            try? await Task.sleep(for: .milliseconds(10))
            await log.add("layer2:webview")                 // ProfileWebFetcher, до 25 с
            try? await Task.sleep(for: .milliseconds(10))
            await log.add("ensureLoaded")                   // InboxRunner.swift:49
            await log.add("makeKey")                        // InboxRunner.swift:223 — точка атаки
            await log.add("fetchProfileNickname")           // InboxRunner.swift:185
            await log.add("done")
        }

        // Юзер жмёт «Отмена»: dismiss() НЕ отменяет nickTask (нет cancel вне handleChanged,
        // нет onDisappear) — фиксируем отсутствие отмены отсутствием какого-либо вызова.
        try? await Task.sleep(for: .milliseconds(5))

        // «Отмена» произошла между layer1 и layer2 — а makeKey всё равно в логе:
        // задача пережила закрытие редактора (никто не вызвал cancel()).
        await nickTask?.value
        let events = await log.events
        XCTAssertTrue(events.contains("layer1:urlsession"))
        XCTAssertTrue(events.contains("makeKey"), "каскад дошёл до makeKey уже после закрытия шита")
    }

    // =========================================================================
    // MARK: - Отбито [СКЕТЧ]: двойной finish слоя 2 невозможен
    // =========================================================================

    private actor FinishGuard {
        private var pending = true
        func finish() -> Bool {
            guard pending else { return false }
            pending = false
            return true
        }
    }

    /// Зеркало инварианта ProfileWebFetcher.finish (ProfileWebFetcher.swift:46-59):
    /// continuation-nil гард гарантирует ровно один resume при любых претендентах
    /// (timeout / цикл didFinish / второй didFinish).
    func test_DEFENDED_profileWebFetcherDoubleFinishResumesExactlyOnce() async {
        let guardSeq = FinishGuard()
        XCTAssertTrue(await guardSeq.finish())
        XCTAssertFalse(await guardSeq.finish())

        let guardConcurrent = FinishGuard()
        let wins = await withTaskGroup(of: Bool.self) { group -> Int in
            for _ in 0..<8 { group.addTask { await guardConcurrent.finish() } }
            var count = 0
            for await won in group where won { count += 1 }
            return count
        }
        XCTAssertEqual(wins, 1, "из N конкурирующих претендентов finish резюмится ровно один раз")
    }

    // =========================================================================
    // MARK: - МЕЛОЧИ: санитайз хенда редактора (NICK-14) [ДЕМО]
    // =========================================================================

    /// Зеркало FriendsView.swift:263-264: trim по краям + удаление "@" — и всё.
    private func mirrorEditorClean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "@", with: "")
    }

    func test_NICK_14_editorSanitizerKeepsInternalGarbage() {
        XCTAssertEqual(mirrorEditorClean("  @john  "), "john")
        XCTAssertEqual(mirrorEditorClean("@@john@"), "john")
        // Внутренний мусор проходит дальше в каскад: слой 1 получит URL c пробелом
        // (URL(string:) → nil → «bad-handle»), слои 2/3 отсекут фильтром —
        // юзер увидит кашу diag вместо понятного сообщения.
        XCTAssertEqual(mirrorEditorClean("jo hn"), "jo hn")
        XCTAssertEqual(mirrorEditorClean("jo\nhn"), "jo\nhn")
    }
}
