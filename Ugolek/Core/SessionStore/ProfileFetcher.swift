import Foundation

/// Часть B/C плана handle-verification: чтение публичного профиля tiktok.com/@{handle}.
/// Ник извлекается из embedded JSON (__UNIVERSAL_DATA_FOR_REHYDRATION__ / SIGI_STATE),
/// причём узел выбирается по совпадению uniqueId == handle — чужие ники из
/// рекомендаций отсекаются (PLAN-11). Страница бот-фильтра данных не содержит → .blocked.
@MainActor
enum ProfileFetcher {
    enum Outcome {
        case found(nickname: String)
        case blocked     // страница отдалась, но данных профиля в ней нет (бот-фильтр?)
        case missing     // профиль не существует / 404 / сеть недоступна
    }

    static func fetch(handle: String) async -> Outcome {
        guard let url = URL(string: "https://www.tiktok.com/@\(handle)") else { return .missing }
        var request = URLRequest(url: url)
        request.setValue(SessionStore.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return .missing }
        guard let html = String(data: data, encoding: .utf8),
              let json = embeddedJSON(from: html) else { return .blocked }

        if let nick = findNickname(in: json, uniqueId: handle.lowercased()) {
            return .found(nickname: nick)
        }
        return .blocked
    }

    /// Вырезаем содержимое <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__">…</script> как JSON.
    private static func embeddedJSON(from html: String) -> Any? {
        guard let openRange = html.range(of: "<script id=\"__UNIVERSAL_DATA_FOR_REHYDRATION__\"[^>]*>",
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
}
