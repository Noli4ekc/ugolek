import Foundation

struct AppSettings: Codable, Equatable {
    var messageText: String = "Привет! Не дадим нашему огоньку погаснуть! 🔥"
    var dailyHour: Int = 10
    var dailyMinute: Int = 0
    var useRandomMessages: Bool = false
    var skipUnreachable: Bool = true
}
