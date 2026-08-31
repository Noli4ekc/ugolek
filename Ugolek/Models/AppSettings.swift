import Foundation

struct AppSettings: Codable, Equatable {
    var messageText: String = "Привет! Не дадим нашему огоньку погаснуть! 🔥"
    var dailyHour: Int = 10
    var dailyMinute: Int = 0
    var useRandomMessages: Bool = false
    var skipUnreachable: Bool = true
    var messageOnlyWithFlame: Bool = true
    var fastMode: Bool = false
    var recipientVerification: Bool = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case messageText, dailyHour, dailyMinute, useRandomMessages, skipUnreachable, messageOnlyWithFlame, fastMode, recipientVerification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messageText = try c.decodeIfPresent(String.self, forKey: .messageText)
            ?? "Привет! Не дадим нашему огоньку погаснуть! 🔥"
        dailyHour = try c.decodeIfPresent(Int.self, forKey: .dailyHour) ?? 10
        dailyMinute = try c.decodeIfPresent(Int.self, forKey: .dailyMinute) ?? 0
        useRandomMessages = try c.decodeIfPresent(Bool.self, forKey: .useRandomMessages) ?? false
        skipUnreachable = try c.decodeIfPresent(Bool.self, forKey: .skipUnreachable) ?? true
        messageOnlyWithFlame = try c.decodeIfPresent(Bool.self, forKey: .messageOnlyWithFlame) ?? true
        fastMode = try c.decodeIfPresent(Bool.self, forKey: .fastMode) ?? false
                recipientVerification = try c.decodeIfPresent(Bool.self, forKey: .recipientVerification) ?? true
    }
}
