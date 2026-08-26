import Foundation

/// Часть B/C плана handle-verification: чтение публичного профиля tiktok.com/@{handle}.
/// Ник извлекается из embedded JSON (__UNIVERSAL_DATA_FOR_REHYDRATION__ / SIGI_STATE),
/// причём узел выбирается по совпадению uniqueId == handle — чужие ники из
/// рекомендаций отсекаются (PLAN-11). Страница бот-фильтра данных не содержит → .blocked.
/// 404 → .missing с суточным негативным кэшем (NICK-06): мёртвые друзья не дёргают
/// TikTok каждый прогон. Прочие не-200 (403/429/бот) → .blocked.
@MainActor
enum ProfileFetcher {
    enum Outcome {
        case found(nickname: String)
        case blocked(diag: String)   // страница отдалась, но данных профиля нет
        case missing(diag: String)   // профиль не существует (404, кэшируется)
    }

    private static var missingUntil: [String: Date] = [:]
    private static let missingTTL: TimeInterval = 24 * 3600

    static func fetch(handle: String) async -> Outcome {
        let key = handle.lowercased()
        if let until = missingUntil[key], until > Date() {
            return .missing(diag: "кэш: недавно не найден")
        }

        guard let url = URL(string: "https://www.tiktok.com/@\(handle)") else {
            return .missing(diag: "bad-handle")
        }
        var request = URLRequest(url: url)
        request.setValue(SessionStore.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .missing(diag: "сеть недоступна")
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        let diag = "http=\(http.statusCode) size=\(data.count)"
            + " uniData=\(html.contains("__UNIVERSAL_DATA_FOR_REHYDRATION__") ? "да" : "нет")"
            + " sigi=\(html.contains("SIGI_STATE") ? "да" : "нет")"
            + " nickAny=\(html.contains("\"nickname\"") ? "да" : "нет")"

        if http.statusCode == 404 {
            missingUntil[key] = Date().addingTimeInterval(missingTTL)
            return .missing(diag: diag)
        }
        guard http.statusCode == 200 else { return .blocked(diag: diag + " (не-200)") }

        // 1) embedded JSON — два известных контейнера
        for marker in ["__UNIVERSAL_DATA_FOR_REHYDRATION__", "SIGI_STATE"] {
            if let json = embeddedJSON(from: html, marker: marker),
               let nick = findNickname(in: json, uniqueId: key) {
                return .found(nickname: nick)
            }
        }

        // 2) сырой фолбэк: находим "uniqueId":"<handle>" и берём "nickname" в окне рядом
        if let nick = rawNicknameNear(html: html, handle: key) {
            return .found(nickname: nick)
        }

        return .blocked(diag: diag)
    }

    private static func embeddedJSON(from html: String, marker: String) -> Any? {
        guard let openRange = html.range(of: "<script id=\"\(marker)\"[^>]*>",
                                         options: .regularExpression) else { return nil }
        guard let closeRange = html.range(of: "</script>", range: openRange.upperBound..<html.endIndex) else { return nil }
        let raw = String(html[openRange.upperBound..<closeRange.lowerBound])
        return try? JSONSerialization.jsonObject(with: Data(raw.utf8))
    }

    /// Рекурсивный поиск словаря пользователя: uniqueId совпадает → берём его nickname.
    private static func findNickname(in node: Any, uniqueId: String) -> String? {
        if let dict = node as? [String: Any] {
            if let uid = dict["uniqueId"] as? String,
               uid.lowercased() == uniqueId,
               let nick = dict["nickname"] as? String,
               !nick.isEmpty {
                return nick
            }
            for child in dict.values {
                if let hit = findNickname(in: child, uniqueId: uniqueId) { return hit }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let hit = findNickname(in: child, uniqueId: uniqueId) { return hit }
            }
        }
        return nil
    }

    /// Фолбэк без JSON-парсинга: окно вокруг "uniqueId":"<handle>" (регистронезависимо),
    /// из него — значение "nickname" с учётом экранирования \" и \\ (NICK-08/09).
    private static func rawNicknameNear(html: String, handle: String) -> String? {
        let pattern = "\"uniqueId\"\\s*:\\s*\"\(NSRegularExpression.escapedPattern(for: handle))\""
        guard let range = html.range(of: pattern, options: .regularExpression) else { return nil }
        let start = html.index(range.lowerBound, offsetBy: -300, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(range.upperBound, offsetBy: 900, limitedBy: html.endIndex) ?? html.endIndex
        let segment = html[start..<end].lowercased()

        guard let nickRange = segment.range(of: "\"nickname\":\"") else { return nil }
        let after = segment[nickRange.upperBound...]

        var raw = ""
        var cursor = after.startIndex
        while cursor < after.endIndex {
            let ch = after[cursor]
            if ch == "\"" { break }                       // конец значения
            if ch == "\\" {                               // экранированный символ — берём пару целиком
                let next = after.index(after: cursor)
                guard next < after.endIndex else { break }
                raw.append(ch)
                raw.append(after[next])
                cursor = after.index(after: next)
            } else {
                raw.append(ch)
                cursor = after.index(after: cursor)
            }
        }

        var nick = raw.replacingOccurrences(of: "\\/", with: "/")
        nick = decodeUnicodeEscapes(nick)
        nick = nick.replacingOccurrences(of: "\\\"", with: "\"")
        nick = nick.replacingOccurrences(of: "\\\\", with: "\\")
        return nick.isEmpty ? nil : nick
    }

    /// Декодирует \uXXXX, включая суррогатные пары эмодзи (NICK-02):
    /// одиночная старшая/младшая суррогата превращается в U+FFFD, а не теряется.
    private static func decodeUnicodeEscapes(_ s: String) -> String {
        guard s.contains("\\u") else { return s }
        let chars = Array(s)
        var bytes = [UInt8]()
        var i = 0

        // \uXXXX в позиции a → кодовая единица; иначе nil
        func hexEscape(at a: Int) -> UInt32? {
            guard a + 5 < chars.count, chars[a] == "\\", chars[a + 1] == "u" else { return nil }
            var v: UInt32 = 0
            for k in (a + 2)...(a + 5) {
                guard let d = chars[k].hexDigitValue else { return nil }
                v = v << 4 | UInt32(d)
            }
            return v
        }

        while i < chars.count {
            if chars[i] == "\\", let high = hexEscape(at: i) {
                i += 6
                if (0xD800...0xDBFF).contains(high), let low = hexEscape(at: i),
                   (0xDC00...0xDFFF).contains(low) {
                    // корректная суррогатная пара (эмодзи и др.) → единый скаляр
                    i += 6
                    let scalar = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                    bytes.append(contentsOf: Unicode.Scalar(scalar)!.utf8)
                } else if (0xD800...0xDFFF).contains(high) {
                    bytes.append(contentsOf: [0xEF, 0xBF, 0xBD])  // битая суррогата → U+FFFD
                } else if let scalar = Unicode.Scalar(high) {
                    bytes.append(contentsOf: scalar.utf8)
                } else {
                    bytes.append(contentsOf: [0xEF, 0xBF, 0xBD])
                }
            } else {
                bytes.append(contentsOf: String(chars[i]).utf8)
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
