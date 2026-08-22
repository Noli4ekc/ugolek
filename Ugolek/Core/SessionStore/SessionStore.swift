import Foundation
import Observation
import WebKit

@Observable
final class SessionStore {
    static let shared = SessionStore()

    private(set) var isLoggedIn = false
    private(set) var lastChecked: Date?

    static let sessionKey = "tiktok_sessionid"
    static let uaKey = "tiktok_login_ua"
    static let cookiesKey = "tiktok_cookies_json"

    static let desktopUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    var sessionID: String? { KeychainStore.string(forKey: Self.sessionKey) }
    var savedUserAgent: String? {
        KeychainStore.string(forKey: Self.uaKey) ?? Self.desktopUserAgent
    }

    private init() { refresh() }

    func refresh() {
        lastChecked = .now
        isLoggedIn = !(sessionID ?? "").isEmpty
    }

    func save(sessionID: String, userAgent: String?) {
        guard !sessionID.isEmpty else { return }
        KeychainStore.setString(sessionID, forKey: Self.sessionKey)
        if let userAgent, !userAgent.isEmpty {
            KeychainStore.setString(userAgent, forKey: Self.uaKey)
        }
        refresh()
    }

    func saveCookies(_ cookies: [HTTPCookie]) {
        let payload = cookies.map { cookie in
            [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path,
            ]
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        KeychainStore.setString(json, forKey: Self.cookiesKey)
    }

    func restoreCookies(into store: WKHTTPCookieStore) async {
        guard let json = KeychainStore.string(forKey: Self.cookiesKey),
              let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return }
        for item in list {
            guard let name = item["name"],
                  let value = item["value"],
                  let domain = item["domain"] else { continue }
            let cookie = HTTPCookie(properties: [
                .domain: domain,
                .path: item["path"] ?? "/",
                .name: name,
                .value: value,
                .secure: true,
            ])
            guard let cookie else { continue }
            await store.setCookie(cookie)
        }
    }

    func invalidate() {
        KeychainStore.remove(forKey: Self.sessionKey)
        KeychainStore.remove(forKey: Self.cookiesKey)
        refresh()
    }

    func logout() {
        KeychainStore.remove(forKey: Self.sessionKey)
        KeychainStore.remove(forKey: Self.uaKey)
        let dataStore = WKWebsiteDataStore.default()
        Task {
            let records = await dataStore.dataRecords(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()
            )
            let tiktokRecords = records.filter {
                $0.displayName.contains("tiktok") || $0.displayName.contains("byteoversea")
            }
            await dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                for: tiktokRecords
            )
        }
        refresh()
    }
}
