import Foundation

struct Friend: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var handle: String
    var label: String = ""
    var isEnabled: Bool = true
    var isGroup: Bool = false
    var hasFlame: Bool = true
    var lastSentDay: String?
    var sentCount: Int = 0
    var failCount: Int = 0

    var displayName: String { label.isEmpty ? handle : label }

    init(handle: String) {
        self.handle = handle
    }

    private enum CodingKeys: String, CodingKey {
        case id, handle, label, isEnabled, isGroup, hasFlame, lastSentDay, sentCount, failCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        handle = try c.decode(String.self, forKey: .handle)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isGroup = try c.decodeIfPresent(Bool.self, forKey: .isGroup) ?? false
        hasFlame = try c.decodeIfPresent(Bool.self, forKey: .hasFlame) ?? true
        lastSentDay = try c.decodeIfPresent(String.self, forKey: .lastSentDay)
        sentCount = try c.decodeIfPresent(Int.self, forKey: .sentCount) ?? 0
        failCount = try c.decodeIfPresent(Int.self, forKey: .failCount) ?? 0
    }
}
