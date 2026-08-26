import Foundation
import CoreLocation

// Держатель фоновой геолокации: пока активна аренда, iOS не замораживает процесс,
// поэтому WebView успевает отправить все сообщения даже при свёрнутом приложении.
@MainActor
final class LocationKeeper: NSObject, CLLocationManagerDelegate {
    static let shared = LocationKeeper()

    private let manager = CLLocationManager()
    private var acquireCount = 0
    private var persistent = false
    private var watchdog: Task<Void, Never>?
    private var lastActivity = Date()

    /// Разовая аренда гаснет, если прогресса не было дольше этого интервала.
    static let staleInterval: TimeInterval = 900

    var permissionStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    var isHolding: Bool {
        acquireCount > 0 || persistent
    }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Запросить разрешение «Всегда» (из экрана настроек).
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    /// Аренда на время прогона (уровень 1).
    func acquire() {
        acquireCount += 1
        startIfNeeded()
        resetWatchdog()
    }

    /// Отметка живости от движка: каждый шаг прогресса продлевает аренду.
    func poke() {
        lastActivity = Date()
    }

    func release() {
        guard acquireCount > 0 else { return }
        acquireCount -= 1
        stopIfNeeded()
    }

    /// Постоянная аренда для авто-режима (уровень 3).
    func startPersistent() {
        persistent = true
        startIfNeeded()
    }

    func stopPersistent() {
        persistent = false
        stopIfNeeded()
    }

    private func startIfNeeded() {
        guard isHolding else { return }
        // BG-05: установка allowsBackgroundLocationUpdates без выданного
        // разрешения (.notDetermined/.denied) кидает NSInternalInconsistencyException.
        // Аренду не глушим (watchdog и счётчик живут), просто не трогаем апдейты,
        // пока пользователь не ответил на запрос.
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    private func stopIfNeeded() {
        guard !isHolding else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        watchdog?.cancel()
        watchdog = nil
    }

    // Сторож: гасим разовую аренду, только если 15 минут не было прогресса —
    // долгий, но живой прогон пикает poke() на каждом шаге и потому бессрочен.
    private func resetWatchdog() {
        watchdog?.cancel()
        lastActivity = Date()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                if self.acquireCount == 0 { return }
                if Date().timeIntervalSince(self.lastActivity) > Self.staleInterval {
                    while self.acquireCount > 0 { self.release() }
                    return
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Разрешение забрали во время постоянной аренды — гасим режим
            if self.persistent && manager.authorizationStatus != .authorizedAlways {
                self.persistent = false
                self.stopIfNeeded()
                NotificationCenter.default.post(name: .geoPermissionRevoked, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let geoPermissionRevoked = Notification.Name("ugolek.geoPermissionRevoked")
}
