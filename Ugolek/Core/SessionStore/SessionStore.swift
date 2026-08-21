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
