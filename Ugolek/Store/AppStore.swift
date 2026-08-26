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
        var seen = Set(friends.map { $0.handle.lowercased() })
        var added = 0
        for friend in imported {
            let key = friend.handle.lowercased()
            // дедуп и против уже существующих друзей, и против дублей внутри самого файла
            if seen.contains(key) { continue }
            seen.insert(key)
            friends.append(friend)
            added += 1
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

        // день берём от СТАРТА прогона: рассылка, перешагнувшая полночь,
        // не должна превращаться в «непродлённый» вчера-день
        let today = Day.string(from: run.date)
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

    /// Часть D/E: отметить «стрик продлён сегодня» без отправки.
    func markStreakMaintainedToday(_ id: UUID) {
        guard let i = friends.firstIndex(where: { $0.id == id }) else { return }
        friends[i].lastSentDay = Day.today()
        persist(.friends)
    }

    /// Часть E: снять ручную отметку (вернуть друга в очередь).
    func resetSentDay(_ id: UUID) {
        guard let i = friends.firstIndex(where: { $0.id == id }),
              friends[i].lastSentDay != nil else { return }
        friends[i].lastSentDay = nil
        persist(.friends)
    }

    /// Битый файл не затираем молча: уводим в карантин рядом с оригиналом,
    /// чтобы данные можно было вытащить руками, а следующий persist начал с чистого листа.
    private func loadJSON<T: Decodable>(_ type: T.Type, _ file: StoreFile) -> T? {
        let url = baseURL.appendingPathComponent(file.rawValue)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let backup = baseURL.appendingPathComponent("\(file.rawValue).corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    private func loadAll() {
        friends = loadJSON([Friend].self, .friends) ?? []
        if let saved = loadJSON(AppSettings.self, .settings) { settings = saved }
        runs = loadJSON([RunRecord].self, .runs) ?? []
    }
}
