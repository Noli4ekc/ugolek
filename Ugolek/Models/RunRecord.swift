import Foundation

enum FriendSendStatus: String, Codable {
    case sent
    case skipped
    case failed
}

struct FriendResult: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var friendId: UUID
    var handle: String
    var status: FriendSendStatus
    var detail: String?
}

struct RunRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date = .now
    var durationSeconds: Double = 0
    var results: [FriendResult] = []

    var sentCount: Int { results.filter { $0.status == .sent }.count }
    var failedCount: Int { results.filter { $0.status == .failed }.count }
    var skippedCount: Int { results.filter { $0.status == .skipped }.count }
}
