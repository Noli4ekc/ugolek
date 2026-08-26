import Foundation

/// Обёртка для Darwin-уведомлений между расширением и приложением.
/// UgolekApp — struct, а Unmanaged требует class; используем глобальный NSObject.
private final class DarwinHost: NSObject {}

enum DarwinNotifier {
    private static let host = DarwinHost()
    private static var callbacks: [String: () -> Void] = [:]
    private static var registered = false

    static func observe(_ name: String, callback: @escaping () -> Void) {
        callbacks[name] = callback
        if !registered {
            registered = true
            // Единый C-callback без захвата контекста — диспетчеризуем сами
            let callbackPointer: CFNotificationCenterCallBack = { _, _, rawName, _, _ in
                guard let rawName else { return }
                let key = rawName.takeUnretainedValue() as String
                DispatchQueue.main.async { callbacks[key]?() }
            }
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(host).toOpaque(),
                callbackPointer,
                "ugolek.run.requested" as CFString,
                nil,
                .deliverImmediately
            )
        }
    }
}
