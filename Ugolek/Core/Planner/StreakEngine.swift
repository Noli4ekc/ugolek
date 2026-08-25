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

        var logLines: [String] = []
        var lastRandomMessage: String? = nil
        InboxRunner.shared.onLog = { logLines.append($0) }
        defer { InboxRunner.shared.onLog = nil }

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
            let outgoingMessage = store.settings.useRandomMessages
                ? MessagePool.random(excluding: lastRandomMessage)
                : store.settings.messageText
            let reply = await InboxRunner.shared.send(
                to: friend.handle,
                message: outgoingMessage,
                isGroup: friend.isGroup,
                dryRun: dryRun,
                fast: store.settings.fastMode
            )
            if store.settings.useRandomMessages, reply.ok ?? false {
                // исключаем на следующем шаге именно отправленную фразу, а не дефолтный текст
                lastRandomMessage = outgoingMessage
            }
            let ok = reply.ok ?? false
            let status: FriendSendStatus = ok ? .sent : (store.settings.skipUnreachable ? .skipped : .failed)
            results.append(FriendResult(
                friendId: friend.id,
                handle: friend.handle,
                status: status,
                detail: ok ? nil : (reply.error ?? reply.detail)
            ))

            if !ok && !store.settings.skipUnreachable { break }
            if index < targets.count - 1 {
                let pauseRange: ClosedRange<Double> = store.settings.fastMode ? 0.8...1.6 : 2...6
                try? await Task.sleep(for: .seconds(Double.random(in: pauseRange)))
            }
        }

        let record = RunRecord(
            date: start,
            durationSeconds: Date().timeIntervalSince(start),
            results: results,
            log: logLines.isEmpty ? nil : logLines.suffix(400).joined(separator: "\n")
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
