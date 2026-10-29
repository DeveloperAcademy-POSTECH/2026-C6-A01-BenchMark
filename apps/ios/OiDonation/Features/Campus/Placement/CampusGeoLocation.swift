// Created by 이돈혁

import CoreLocation
import Observation

@MainActor @Observable final class CampusGeoLocation: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var message = "위치 권한을 확인하고 있어요."
    @ObservationIgnored private let manager = CLLocationManager()
    private var active = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }
    func start() {
        active = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            message = manager.accuracyAuthorization == .fullAccuracy
                ? "하늘이 보이는 곳에서 GPS를 확인해 주세요."
                : "설정에서 ‘정확한 위치’를 허용해 주세요."
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            location = nil
            message = "설정에서 이 앱의 위치 권한을 허용해 주세요."
        @unknown default: location = nil; message = "위치 권한을 확인해 주세요."
        }
    }
    func stop() { active = false; manager.stopUpdatingLocation(); location = nil }
    func isReady(for target: CampusPlacement) -> Bool {
        guard active, let location, manager.accuracyAuthorization == .fullAccuracy,
              manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        else { return false }
        return CampusLocationQuality.allowsPlacement(latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy,
            timestamp: location.timestamp, target: target)
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.active else { return }
            self.location = nil
            self.start()
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            guard self.active else { return }
            self.location = latest
            self.message = "GPS 오차가 15m 이하이고 목표 지점 25m 안일 때 배치할 수 있어요."
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.active else { return }
            self.location = nil
            self.message = "위치를 확인하지 못했어요. 설정과 주변 환경을 확인해 주세요."
        }
    }
}
