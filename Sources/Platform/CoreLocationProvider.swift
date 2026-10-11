import AppKit
import CoreLocation
import Daylight

// MARK: - CoreLocation provider
// The location port's adapter: Location Services authorization and a one-shot fix at kilometre accuracy. The manager
// is made on the main actor, so its delegate calls arrive there (checked at run time by the `@preconcurrency`
// conformance). The fix is handed on precise; Daylight rounds it.

@MainActor
final class CoreLocationProvider: NSObject, LocationPort, @preconcurrency CLLocationManagerDelegate {
    var onUpdate: (LocationUpdate) -> Void = { _ in }
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorization: LocationAuthorization { Self.authorization(manager.authorizationStatus) }

    /// Setting the delegate makes CoreLocation report the current authorization.
    func start() {
        manager.delegate = self
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestFix() {
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onUpdate(.authorizationChanged(Self.authorization(manager.authorizationStatus)))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onUpdate(.fixed(Coordinates(
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onUpdate(.failed(reason: error.localizedDescription))
    }

    private static func authorization(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways: return .authorized
        @unknown default: return .unknown
        }
    }
}

// MARK: - System appearance

/// The appearance port's adapter: the app's effective appearance, Light or Dark.
@MainActor
final class SystemAppearance: AppearancePort {
    var current: Appearance {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
