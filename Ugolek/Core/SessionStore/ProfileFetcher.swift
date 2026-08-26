import Foundation

/// Часть B/C плана handle-verification: чтение публичного профиля tiktok.com/@{handle}.
/// Ник извлекается из embedded JSON (__UNIVERSAL_DATA_FOR_REHYDRATION__ / SIGI_STATE),
/// узел выбирается по совпадению uniqueId == handle — чужие ники из рекомендаций отсекаются.
/// TikTok может отдать iOS-клиенту страницу без данных (бот-фильтр) — тогда .blocked
/// несёт diag-строку, по которой видно, что именно пришло.
@MainActor
enum ProfileFetcher {
    enum Outcome {
        case found(nickname: String)
        case blocked(diag: String)   // 200, но данных профиля нет
        case missing(diag: String)   // 404 / сеть / профиль не существует
    }

    static func fetch(handle: String) async -> Outcome {
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

        guard http.statusCode == 200 else { return .missing(diag: diag) }

        // 1) embedded JSON — два известных контейнера
        for marker in ["__UNIVERSAL_DATA_FOR_REHYDRATION__", "SIGI_STATE"] {
            if let json = embeddedJSON(from: html, marker: marker),
               let nick = findNickname(in: json, uniqueId: handle.lowercased()) {
                return .found(nickname: nick)
            }
        }

        // 2) сырой фолбэк: находим "uniqueId":"<handle>" и берём "nickname" в окне рядом
        if let nick = rawNicknameNear(html: html, handle: handle) {
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

    /// Фолбэк без JSON-парсинга: окно вокруг "uniqueId":"<handle>", из него — "nickname":"…".
    private static func rawNicknameNear(html: String, handle: String) -> String? {
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
        nick = decodeUnicodeEscapes(nick)
        return nick.isEmpty ? nil : nick
    }

    private static func decodeUnicodeEscapes(_ s: String) -> String {
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
}
