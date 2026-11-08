// Created by 이돈혁

import Foundation
import simd

/// Geographic placement for published stories and isolated device checks; not donation approval.
struct CampusPlacement: Codable, Identifiable, Hashable {
    static let heightRange = 0.4...2.0
    let id: UUID
    let storyID: String
    let latitude: Double
    let longitude: Double
    let heightMeters: Double
    let headingDegrees: Double
    let model: String

    var heightCentimeters: Int { Int((heightMeters * 100).rounded()) }

    init(id: UUID = UUID(), storyID: String, latitude: Double, longitude: Double,
         heightMeters: Double = 1, headingDegrees: Double = 0) {
        self.id = id; self.storyID = storyID
        self.latitude = latitude; self.longitude = longitude
        self.heightMeters = heightMeters; self.headingDegrees = headingDegrees
        model = "helmet-oi"
    }

    func validated() throws -> Self {
        guard model == "helmet-oi", !storyID.isEmpty, storyID.count <= 100,
              [latitude, longitude, heightMeters, headingDegrees].allSatisfy(\.isFinite),
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              Self.heightRange.contains(heightMeters), (0..<360).contains(headingDegrees)
        else { throw CampusPlacementError.invalid }
        return self
    }

    static func story(id: UUID, latitude: Double, longitude: Double,
                      heightMeters: Double?, headingDegrees: Double?) -> Self? {
        let height = heightMeters ?? 1
        let allowedHeight = height.isFinite ? min(heightRange.upperBound, max(heightRange.lowerBound, height)) : 1
        return try? Self(id: id, storyID: id.uuidString, latitude: latitude, longitude: longitude,
                         heightMeters: allowedHeight, headingDegrees: wrappedHeading(headingDegrees ?? 0)).validated()
    }

    static func wrappedHeading(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let angle = degrees.truncatingRemainder(dividingBy: 360)
        return angle < 0 ? angle + 360 : angle
    }

    func distance(latitude lat: Double, longitude lon: Double) -> Double {
        let r = Double.pi / 180
        let h = pow(sin((lat - latitude) * r / 2), 2)
            + cos(latitude * r) * cos(lat * r) * pow(sin((lon - longitude) * r / 2), 2)
        let clamped = min(1, max(0, h))
        return 6_371_000 * 2 * atan2(sqrt(clamped), sqrt(1 - clamped))
    }

    /// AR world units are metres, unlike the campus map's 0.12 units/metre.
    func offsetMeters(fromLatitude lat: Double, longitude lon: Double) -> SIMD3<Float> {
        let xy = CampusGeoreference(longitude: lon, latitude: lat, scale: 1)
            .xy(longitude: longitude, latitude: latitude)
        return SIMD3(Float(xy.x), 0, Float(-xy.y))
    }
}

enum CampusPlacementError: LocalizedError {
    case invalid, outside, unknownStory, unreadable, capacity
    var errorDescription: String? {
        switch self {
        case .invalid: "오이의 좌표·크기·방향을 확인해 주세요."
        case .outside: "캠퍼스 경계 안의 건물 밖 공간을 선택해 주세요."
        case .unknownStory: "연결할 예시 스토리를 다시 선택해 주세요."
        case .unreadable: "저장한 배치를 읽지 못했어요. 원본 파일은 보존되며 새 저장은 중단됩니다."
        case .capacity: "기기 테스트에서는 오이를 최대 20개까지 저장할 수 있어요."
        }
    }
}

/// Prototype thresholds, not a final collection policy or a positioning guarantee.
enum CampusLocationQuality {
    static let radiusMeters = 25.0
    static let maximumAccuracy = 15.0
    static func allowsFix(latitude: Double, longitude: Double, accuracy: Double,
                          timestamp: Date, now: Date = Date()) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
            && (-180...180).contains(longitude) && accuracy.isFinite
            && (0...maximumAccuracy).contains(accuracy)
            && abs(timestamp.timeIntervalSince(now)) < 10
    }
    static func allowsPlacement(latitude: Double, longitude: Double, accuracy: Double,
                                timestamp: Date, target: CampusPlacement, now: Date = Date()) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude)
            && (-180...180).contains(longitude) && accuracy.isFinite
            && (0...maximumAccuracy).contains(accuracy)
            && abs(timestamp.timeIntervalSince(now)) < 10
            && target.distance(latitude: latitude, longitude: longitude) <= radiusMeters
    }
}
