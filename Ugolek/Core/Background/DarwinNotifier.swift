import Foundation

/// Обёртка для Darwin-уведомлений.
/// UgolekApp — struct, а Unmanaged требует class; используем глобальный объект.
private final class DarwinObserverHost: NSObject {}

enum DarwinNotifier {
    private static let host = DarwinObserverHost()
    private static var callbacks: [String: () -> Void] = [:]

    static func observe(_ name: String, callback: @escaping () -> Void) {
        callbacks[name] = callback
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(host).toOpaque(),
            { _, _, _, _, _ in
                DispatchQueue.main.async { callbacks[name]?() }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }
}
