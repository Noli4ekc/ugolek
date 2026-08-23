import Foundation
import Observation

@Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var friends: [Friend] = []
    var settings = AppSettings() { didSet { persist(.settings) } }
    private(set) var runs: [RunRecord] = []

    private let maxRuns = 50

    private init() { loadAll() }

    func add(_ friend: Friend) {
        friends.append(friend)
        persist(.friends)
    }

    func update(_ friend: Friend) {
        guard let i = friends.firstIndex(where: { $0.id == friend.id }) else { return }
        friends[i] = friend
        persist(.friends)
    }

    func delete(_ friend: Friend) {
        friends.removeAll { $0.id == friend.id }
        persist(.friends)
    }

    func exportFriendsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(friends),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    func importFriendsJSON(_ json: String) -> Int {
        guard let data = json.data(using: .utf8),
              let imported = try? JSONDecoder().decode([Friend].self, from: data) else { return 0 }
        let existingHandles = Set(friends.map { $0.handle.lowercased() })
        var added = 0
        for friend in imported {
            if !existingHandles.contains(friend.handle.lowercased()) {
                friends.append(friend)
                added += 1
            }
        }
        if added > 0 { persist(.friends) }
        return added
    }

    var friendsDueToday: [Friend] {
        let today = Day.today()
        return friends.filter { friend in
            guard friend.isEnabled, friend.lastSentDay != today else { return false }
            if settings.messageOnlyWithFlame && !friend.hasFlame { return false }
            return true
        }
    }

    var sentTodayCount: Int {
        let today = Day.today()
        return friends.filter { $0.lastSentDay == today }.count
    }

    func record(_ run: RunRecord) {
        runs.insert(run, at: 0)
        if runs.count > maxRuns { runs.removeLast(runs.count - maxRuns) }

        let today = Day.today()
        for result in run.results {
            guard let i = friends.firstIndex(where: { $0.id == result.friendId }) else { continue }
            switch result.status {
            case .sent:
                friends[i].sentCount += 1
                friends[i].lastSentDay = today
            case .failed:
                friends[i].failCount += 1
            case .skipped:
                break
            }
        }
        persist(.runs)
        persist(.friends)
    }

    private enum StoreFile: String {
        case friends = "friends.json"
        case settings = "settings.json"
        case runs = "history.json"
    }

    private var baseURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func persist(_ file: StoreFile) {
        let data: Data?
        switch file {
        case .friends: data = try? JSONEncoder().encode(friends)
        case .settings: data = try? JSONEncoder().encode(settings)
        case .runs: data = try? JSONEncoder().encode(runs)
        }
        guard let data else { return }
        try? data.write(to: baseURL.appendingPathComponent(file.rawValue), options: .atomic)
    }

    private func loadAll() {
        let decoder = JSONDecoder()
        let friendsURL = baseURL.appendingPathComponent(StoreFile.friends.rawValue)
        let settingsURL = baseURL.appendingPathComponent(StoreFile.settings.rawValue)
        let runsURL = baseURL.appendingPathComponent(StoreFile.runs.rawValue)

        if let d = try? Data(contentsOf: friendsURL),
           let f = try? decoder.decode([Friend].self, from: d) { friends = f }
        if let d = try? Data(contentsOf: settingsURL),
           let s = try? decoder.decode(AppSettings.self, from: d) { settings = s }
        if let d = try? Data(contentsOf: runsURL),
           let r = try? decoder.decode([RunRecord].self, from: d) { runs = r }
    }
}
