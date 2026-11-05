//
//  BenchLocationService.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/16/26.
//

import CoreLocation
import Observation

@MainActor
@Observable
final class BenchLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var timeout: Task<Void, Never>?
    private var isWaitingForPermission = false
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isLocating = false
    private(set) var location: CLLocation?
    private(set) var focusRequest = 0
    var notice: Notice?

    struct Notice: Identifiable {
        let id = UUID()
        let message: String
        var offersSettings = false
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authorizationStatus = manager.authorizationStatus
    }

    func refreshAuthorization() {
        authorizationStatus = manager.authorizationStatus
        if !isAuthorized { location = nil }
    }

    func locate() {
        guard !isLocating else { return }
        notice = nil
        refreshAuthorization()
        switch authorizationStatus {
        case .notDetermined:
            isWaitingForPermission = true
            isLocating = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            manager.requestLocation()
            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self, self.isLocating else { return }
                self.finish()
                self.notice = Notice(message: "현재 위치를 찾지 못했어요. GPS와 네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
            }
        case .denied:
            notice = Notice(message: "현재 위치를 보려면 설정에서 위치 접근을 허용해 주세요. 위치 권한 없이도 지도를 둘러볼 수 있어요.", offersSettings: true)
        case .restricted:
            notice = Notice(message: "기기 제한으로 위치를 사용할 수 없어요. 위치 권한 없이도 지도를 둘러볼 수 있어요.")
        @unknown default:
            notice = Notice(message: "현재 위치를 사용할 수 없어요. 잠시 후 다시 시도해 주세요.")
        }
    }

    func cancel() {
        isWaitingForPermission = false
        finish()
    }

    private func finish() {
        timeout?.cancel()
        timeout = nil
        isLocating = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAuthorization()
        guard isWaitingForPermission, authorizationStatus != .notDetermined else { return }
        isWaitingForPermission = false
        finish()
        locate()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocating, let latest = locations.last,
              latest.horizontalAccuracy >= 0,
              abs(latest.timestamp.timeIntervalSinceNow) < 60 else { return }
        location = latest
        focusRequest += 1
        finish()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard isLocating else { return }
        finish()
        if let error = error as? CLError, error.code == .denied {
            notice = Notice(message: "위치 서비스를 사용할 수 없어요. 설정에서 위치 서비스와 앱의 위치 접근 권한을 확인해 주세요.", offersSettings: true)
        } else {
            notice = Notice(message: "현재 위치를 찾지 못했어요. GPS와 네트워크 상태를 확인한 뒤 다시 시도해 주세요.")
        }
    }
}
