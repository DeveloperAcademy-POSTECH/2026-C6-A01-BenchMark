//
//  CampusBuildingTarget.swift
//  OiDonation
//
//  Created by Codex on 11/16/26.
//

import Foundation
import CoreGraphics
import simd

/// Lightweight picking volumes from the same footprints/heights used for map labels.
/// No collision mesh is generated for the full campus.
struct CampusBuildingTarget: Identifiable, Equatable {
    let id: String
    let name: String
    let footprint: [SIMD2<Float>]
    let floor: Float
    let roof: Float

    static func catalog(_ data: CampusMapData) -> [Self] {
        let labels = Dictionary(uniqueKeysWithValues: CampusBuildingLabel.catalog(data).map { ($0.id, $0) })
        return data.buildings.compactMap { building in
            guard building.id != CampusEducationSite.retiredBuildingID,
                  let label = labels[building.id], let roof = building.modelRoofZ else { return nil }
            let floor = building.p.map { data.world($0).y }.min() ?? Float(roof) - 1
            return Self(id: building.id, name: label.title,
                footprint: building.p.map { SIMD2(Float($0[0]), Float(-$0[1])) },
                floor: min(floor, Float(roof) - 0.1), roof: Float(roof))
        }
    }

    var center: SIMD3<Float> {
        let xs = footprint.map(\.x), zs = footprint.map(\.y)
        return SIMD3(((xs.min() ?? 0) + (xs.max() ?? 0)) / 2,
                     (floor + roof) / 2, ((zs.min() ?? 0) + (zs.max() ?? 0)) / 2)
    }

    func distance(origin: SIMD3<Float>, direction: SIMD3<Float>) -> Float? {
        guard footprint.count >= 3 else { return nil }
        var hits: [Float] = []
        if abs(direction.y) > 0.00001 {
            for y in [floor, roof] {
                let t = (y - origin.y) / direction.y
                let point = origin + direction * t
                if t >= 0, contains(SIMD2(point.x, point.z)) { hits.append(t) }
            }
        }
        let o = SIMD2(origin.x, origin.z), d = SIMD2(direction.x, direction.z)
        func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
        for i in footprint.indices {
            let a = footprint[i], edge = footprint[(i + 1) % footprint.count] - a
            let denominator = cross(d, edge)
            guard abs(denominator) > 0.00001 else { continue }
            let t = cross(a - o, edge) / denominator, u = cross(a - o, d) / denominator
            let y = origin.y + direction.y * t
            if t >= 0, (0...1).contains(u), (floor...roof).contains(y) { hits.append(t) }
        }
        return hits.min()
    }

    private func contains(_ p: SIMD2<Float>) -> Bool {
        var inside = false, j = footprint.count - 1
        for i in footprint.indices {
            let a = footprint[i], b = footprint[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    static func hit(in buildings: [Self], origin: SIMD3<Float>, direction: SIMD3<Float>) -> Self? {
        buildings.compactMap { building in building.distance(origin: origin, direction: direction).map { (building, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    func cameraRadius(viewport: CGSize, yaw: Float, pitch: Float) -> Float {
        let aspect = Float(max(1, viewport.width) / max(1, viewport.height))
        let tangent = tan(Float(42) * .pi / 360)
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let up = SIMD3<Float>(-sin(yaw) * sin(pitch), cos(pitch), -cos(yaw) * sin(pitch))
        let towardEye = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        return footprint.flatMap { point in [floor, roof].map { SIMD3(point.x, $0, point.y) - center } }
            .reduce(Float(20)) { result, offset in
                max(result, simd_dot(offset, towardEye) + max(abs(simd_dot(offset, right)) / (tangent * aspect * 0.78),
                    abs(simd_dot(offset, up)) / (tangent * 0.65)))
            }
    }
}
