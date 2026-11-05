//
//  CampusCardLocationChecks.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import CoreLocation
import Foundation

@main
struct CampusCardLocationChecks {
    static func main() throws {
        let path = CommandLine.arguments[1]
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let boundary = try CampusPohangBoundary(data: data)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func fix(_ latitude: Double, _ longitude: Double, accuracy: Double = 20, age: TimeInterval = 0) -> CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: longitude), altitude: 0,
                       horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
        }

        let campus = try boundary.classify(fix(36.01261057021347, 129.3197268697784), now: now)
        let northDistrict = try boundary.classify(fix(36.110, 129.347), now: now)
        let offshore = try boundary.classify(fix(36.066, 129.402), now: now)
        let gyeongju = try boundary.classify(fix(35.8562, 129.2628), now: now)
        let seoul = try boundary.classify(fix(37.5665, 126.9780), now: now)
        precondition(campus == .near && northDistrict == .near && gyeongju == .away && seoul == .away && offshore == .away)

        struct BoundaryGeometry: Decodable { let coordinates: [[[[Double]]]] }
        let geometry = try JSONDecoder().decode(BoundaryGeometry.self, from: data)
        let vertex = geometry.coordinates[0][0][0]
        let ambiguous = [
            fix(vertex[1], vertex[0]),
            fix(36.01261057021347, 129.3197268697784, age: 30),
            fix(36.01261057021347, 129.3197268697784, accuracy: 2_000),
            fix(36.01261057021347, 129.3197268697784, accuracy: -1)
        ]
        for location in ambiguous {
            do {
                _ = try boundary.classify(location, now: now)
                preconditionFailure("Uncertain, stale, or invalid location must never authorize either city classification")
            } catch CampusCardLocationError.inaccurate { }
        }
        print("PASS: Pohang two districts, other cities, city edge, accuracy, and stale fixes")
    }
}
