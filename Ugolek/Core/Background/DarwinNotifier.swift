import Foundation

/// Обёртка над CFNotificationCenterGetDarwinNotifyCenter для лёгкой подписки
/// из struct-типов (UgolekApp — struct, Unmanaged требует class).
enum DarwinNotifier {
    private static var observerMap: [String: () -> Void] = [:]

    static func observe(_ name: String, callback: @escaping () -> Void) {
        observerMap[name] = callback
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(DarwinNotifier.self).toOpaque(),
            { _, _, _, _, _ in
                let key = name as String
                DispatchQueue.main.async {
                    observerMap[key]?()
                }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }
}
