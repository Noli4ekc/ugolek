import Foundation

enum Day {
    static func today(_ calendar: Calendar = .current) -> String {
        string(from: .now, calendar: calendar)
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
