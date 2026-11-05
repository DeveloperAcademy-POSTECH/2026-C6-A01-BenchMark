//
//  CampusCardLocation.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import CoreLocation
import Foundation
import MapKit

enum CampusCardProximity: Equatable {
    case near
    case away
}

enum CampusCardLocationError: LocalizedError, Equatable {
    case permissionRequired
    case permissionDenied
    case permissionRestricted
    case locating
    case unavailable
    case inaccurate
    case boundaryUnavailable

    var offersSettings: Bool { self == .permissionDenied }

    var errorDescription: String? {
        switch self {
        case .permissionRequired: "포항시 안에 있는지 확인하려면 위치 권한이 필요해요."
        case .permissionDenied: "설정에서 위치 서비스와 오이기부의 위치 접근을 허용해 주세요."
        case .permissionRestricted: "이 기기에서는 위치를 확인할 수 없어요."
        case .locating: "이미 현재 위치를 확인하고 있어요."
        case .unavailable: "현재 위치를 확인하지 못했어요. 주변 환경을 확인한 뒤 다시 시도해 주세요."
        case .inaccurate: "포항시 안에 있는지 확실히 확인하지 못했어요. 정확한 위치를 허용하거나 다시 시도해 주세요."
        case .boundaryUnavailable: "포항시 경계 자료를 불러오지 못했어요. 앱을 다시 열어 주세요."
        }
    }
}

/// Requests one foreground fix per check. Coordinates stay on the device.
@MainActor
final class CampusCardLocation: NSObject, CLLocationManagerDelegate {
    private struct Request {
        let id: UUID
        let manager: CLLocationManager
        let continuation: CheckedContinuation<CLLocation, Error>
        var requestedFix = false
    }

    private var request: Request?
    private var timeoutTask: Task<Void, Never>?
    private static let boundary = Result<CampusPohangBoundary, Error> { try CampusPohangBoundary.load() }

    func classify(requestPermission: Bool = true) async throws -> CampusCardProximity {
        try Task.checkCancellation()
        guard request == nil else { throw CampusCardLocationError.locating }
        let boundary = try Self.boundary.get()
        let id = UUID()
        let fix: CLLocation = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let manager = CLLocationManager()
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                request = Request(id: id, manager: manager, continuation: continuation)
                manager.delegate = self
                checkAuthorization(for: id, mayPrompt: requestPermission)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, with: .failure(CancellationError())) }
        }
        try Task.checkCancellation()
        return try boundary.classify(fix)
    }

    private func checkAuthorization(for id: UUID, mayPrompt: Bool) {
        guard let request, request.id == id else { return }
        switch request.manager.authorizationStatus {
        case .notDetermined:
            if mayPrompt { request.manager.requestWhenInUseAuthorization() }
            else { finish(id, with: .failure(CampusCardLocationError.permissionRequired)) }
        case .authorizedAlways, .authorizedWhenInUse:
            guard !request.requestedFix else { return }
            self.request?.requestedFix = true
            request.manager.requestLocation()
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                self?.finish(id, with: .failure(CampusCardLocationError.unavailable))
            }
        case .denied: finish(id, with: .failure(CampusCardLocationError.permissionDenied))
        case .restricted: finish(id, with: .failure(CampusCardLocationError.permissionRestricted))
        @unknown default: finish(id, with: .failure(CampusCardLocationError.unavailable))
        }
    }

    private func finish(_ id: UUID, with result: Result<CLLocation, Error>) {
        guard let request, request.id == id else { return }
        self.request = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        request.manager.delegate = nil
        request.manager.stopUpdatingLocation()
        request.continuation.resume(with: result)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let identity = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in
            guard let self, let request, ObjectIdentifier(request.manager) == identity,
                  request.manager.authorizationStatus != .notDetermined else { return }
            checkAuthorization(for: request.id, mayPrompt: false)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let identity = ObjectIdentifier(manager)
        let fix = locations.last
        Task { @MainActor [weak self] in
            guard let self, let request, ObjectIdentifier(request.manager) == identity, request.requestedFix else { return }
            switch request.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if let fix { finish(request.id, with: .success(fix)) }
                else { finish(request.id, with: .failure(CampusCardLocationError.unavailable)) }
            default: checkAuthorization(for: request.id, mayPrompt: false)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let identity = ObjectIdentifier(manager)
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self, let request, ObjectIdentifier(request.manager) == identity else { return }
            let failure: CampusCardLocationError = denied ? .permissionDenied : .unavailable
            finish(request.id, with: .failure(failure))
        }
    }
}

struct CampusPohangBoundary {
    private struct Geometry: Decodable {
        let type: String
        let coordinates: [[[[Double]]]]
    }

    private let polygons: [[[MKMapPoint]]]

    static func load(from bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "pohang-city-boundary", withExtension: "json") else {
            throw CampusCardLocationError.boundaryUnavailable
        }
        do { return try Self(data: Data(contentsOf: url)) }
        catch { throw CampusCardLocationError.boundaryUnavailable }
    }

    init(data: Data) throws {
        let geometry = try JSONDecoder().decode(Geometry.self, from: data)
        guard geometry.type == "MultiPolygon", !geometry.coordinates.isEmpty else {
            throw CampusCardLocationError.boundaryUnavailable
        }
        polygons = try geometry.coordinates.map { polygon in
            guard !polygon.isEmpty else { throw CampusCardLocationError.boundaryUnavailable }
            return try polygon.map { ring in
                guard ring.count >= 4, ring.first == ring.last else {
                    throw CampusCardLocationError.boundaryUnavailable
                }
                return try ring.map { pair in
                    guard pair.count == 2, pair.allSatisfy(\.isFinite) else {
                        throw CampusCardLocationError.boundaryUnavailable
                    }
                    let coordinate = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                    guard CLLocationCoordinate2DIsValid(coordinate) else {
                        throw CampusCardLocationError.boundaryUnavailable
                    }
                    return MKMapPoint(coordinate)
                }
            }
        }
    }

    func classify(_ fix: CLLocation, now: Date = .now) throws -> CampusCardProximity {
        let age = now.timeIntervalSince(fix.timestamp)
        guard CLLocationCoordinate2DIsValid(fix.coordinate),
              (0...1_000).contains(fix.horizontalAccuracy), (-1...15).contains(age) else {
            throw CampusCardLocationError.inaccurate
        }
        let point = MKMapPoint(fix.coordinate)
        let metersPerPoint = MKMetersPerMapPointAtLatitude(fix.coordinate.latitude)
        // A fix is usable only when its uncertainty does not reach the city edge.
        let uncertainty = (fix.horizontalAccuracy + 2) / metersPerPoint
        let limit = uncertainty * uncertainty
        var isInside = false
        for polygon in polygons {
            var insidePolygon = false
            for ring in polygon {
                var insideRing = false
                for (a, b) in zip(ring, ring.dropFirst()) {
                    if Self.distanceSquared(from: point, toSegmentFrom: a, to: b) <= limit {
                        throw CampusCardLocationError.inaccurate
                    }
                    if (a.y > point.y) != (b.y > point.y),
                       point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                        insideRing.toggle()
                    }
                }
                if insideRing { insidePolygon.toggle() }
            }
            isInside = isInside || insidePolygon
        }
        return isInside ? .near : .away
    }

    private static func distanceSquared(from point: MKMapPoint, toSegmentFrom a: MKMapPoint, to b: MKMapPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = dx * dx + dy * dy
        let projection = length > 0 ? ((point.x - a.x) * dx + (point.y - a.y) * dy) / length : 0
        let t = min(1, max(0, projection))
        let x = point.x - (a.x + t * dx)
        let y = point.y - (a.y + t * dy)
        return x * x + y * y
    }
}
