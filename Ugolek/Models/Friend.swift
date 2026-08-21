import Foundation

struct Friend: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var handle: String
    var label: String = ""
    var isEnabled: Bool = true
    var isGroup: Bool = false
    var lastSentDay: String?
    var sentCount: Int = 0
    var failCount: Int = 0

    var displayName: String { label.isEmpty ? handle : label }
}
