import Foundation

@MainActor
enum StreakEngine {
    struct ProgressUpdate {
        let text: String
        let done: Int
        let total: Int
    }

    @discardableResult
    static func run(
        dryRun: Bool = false,
        forceAll: Bool = false,
        onProgress: @escaping (ProgressUpdate) -> Void
    ) async -> RunRecord {
        let store = AppStore.shared
        let start = Date()

        let targets = forceAll
            ? store.friends.filter(\.isEnabled)
            : store.friendsDueToday

        guard !targets.isEmpty else {
            return RunRecord(date: start, durationSeconds: 0, results: [])
        }

        guard SessionStore.shared.isLoggedIn else {
            return failedRun(start: start, message: "Нужен вход в TikTok")
        }

        onProgress(ProgressUpdate(text: "Открываю сообщения TikTok…", done: 0, total: targets.count))
        do {
            try await InboxRunner.shared.ensureLoaded()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return failedRun(start: start, message: message)
        }

        var results: [FriendResult] = []
        for (index, friend) in targets.enumerated() {
            onProgress(ProgressUpdate(
                text: "Пишу \(friend.displayName)…",
                done: index,
                total: targets.count
            ))

            let reply = await InboxRunner.shared.send(
                to: friend.handle,
                message: store.settings.messageText,
                isGroup: friend.isGroup,
                dryRun: dryRun
            )
            let ok = reply.ok ?? false
            results.append(FriendResult(
                friendId: friend.id,
                handle: friend.handle,
                status: ok ? .sent : .failed,
                detail: reply.error ?? reply.detail
            ))

            if !ok && !store.settings.skipUnreachable { break }
            if index < targets.count - 1 {
                try? await Task.sleep(for: .seconds(Double.random(in: 2...6)))
            }
        }

        let record = RunRecord(
            date: start,
            durationSeconds: Date().timeIntervalSince(start),
            results: results
        )
        if !dryRun { store.record(record) }
        return record
    }

    private static func failedRun(start: Date, message: String) -> RunRecord {
        RunRecord(
            date: start,
            durationSeconds: Date().timeIntervalSince(start),
            results: [FriendResult(friendId: UUID(), handle: "—", status: .failed, detail: message)]
        )
    }
}
