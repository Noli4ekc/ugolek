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
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func stopIfNeeded() {
        guard !isHolding else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        watchdog?.cancel()
        watchdog = nil
    }

    // Сторож: разовая аренда не может висеть дольше 15 минут — значит прогон завис.
    private func resetWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(900))
            guard !Task.isCancelled, let self else { return }
            while self.acquireCount > 0 { self.release() }
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
