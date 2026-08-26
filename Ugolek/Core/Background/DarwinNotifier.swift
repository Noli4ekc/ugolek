import Foundation

/// Обёртка для Darwin-уведомлений между расширением и приложением.

private final class DarwinHost: NSObject {}

/// Глобальный C-callback для CFNotificationCenter — global functions are
/// implicitly C-callable; @convention(c) cannot be applied to declarations.
private func _darwinCallback(
    _ center: CFNotificationCenter,
    _ observer: UnsafeMutableRawPointer?,
    _ rawName: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let rawName else { return }
    let key = rawName as String
    DispatchQueue.main.async { DarwinNotifier.handle(key) }
}

enum DarwinNotifier {
    private static let host = DarwinHost()
    private static var callbacks: [String: () -> Void] = [:]

    static func observe(_ name: String, callback: @escaping () -> Void) {
        callbacks[name] = callback
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(host).toOpaque(),
            _darwinCallback,
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    static func handle(_ name: String) {
        callbacks[name]?()
    }
}
