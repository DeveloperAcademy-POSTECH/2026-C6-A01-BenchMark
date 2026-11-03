import Foundation
import CoreGraphics
import simd

/// Names belong to buildings, not every POI/room inside the same building.
struct CampusBuildingLabel {
    let id: String
    let title: String
    let anchor: SIMD3<Float>
    let roof: [SIMD3<Float>]

    static func catalog(_ map: CampusMapData) -> [Self] {
        map.buildings.compactMap { building in
            let sourceName = building.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // The RIST compound is verified, but its individual wing numbers are not.
            // Use its shared name only for explicitly reviewed building IDs.
            let groupName = map.buildingLabelGroups?.first { $0.buildingIDs.contains(building.id) }?.name ?? ""
            let raw = sourceName.isEmpty ? groupName : sourceName
            // An unnamed building or a bare OSM tower number is not a useful name.
            guard !raw.isEmpty, Double(raw) == nil,
                  building.p.count >= 3,
                  building.p.allSatisfy({ $0.count >= 2 && $0[0].isFinite && $0[1].isFinite }),
                  let roofHeight = building.modelRoofZ, roofHeight.isFinite else { return nil }
            let title = raw.components(separatedBy: " (").first ?? raw
            let xs = building.p.map { $0[0] }, ys = building.p.map { $0[1] }
            let cx = (xs.min()! + xs.max()!) / 2, cy = (ys.min()! + ys.max()!) / 2
            func inside(_ x: Double, _ y: Double) -> Bool {
                map.contains(SIMD3(Float(x), 0, Float(-y)), polygon: building.p)
            }
            var anchorXY = SIMD2(cx, cy)
            if !inside(cx, cy) {
                // Concave roofs (C/L/U shapes): keep the anchor on the roof, not the courtyard.
                var points: [SIMD2<Double>] = []
                let minX = xs.min()!, minY = ys.min()!
                let width = xs.max()! - minX, depth = ys.max()! - minY
                for column in 1...19 {
                    for row in 1...19 {
                        let x = minX + width * Double(column) / 20
                        let y = minY + depth * Double(row) / 20
                        if inside(x, y) { points.append(SIMD2(x, y)) }
                    }
                }
                guard let nearest = points.min(by: { simd_distance_squared($0, anchorXY) < simd_distance_squared($1, anchorXY) }) else { return nil }
                anchorXY = nearest
            }
            return Self(id: building.id, title: title,
                        anchor: SIMD3(Float(anchorXY.x), Float(roofHeight) + 0.5, Float(-anchorXY.y)),
                        roof: building.p.map { SIMD3(Float($0[0]), Float(roofHeight), Float(-$0[1])) })
        }
    }

    static func groups(_ map: CampusMapData) -> [Self] {
        let buildings = catalog(map)
        return (map.buildingLabelGroups ?? []).compactMap { group in
            let members = buildings.filter { group.buildingIDs.contains($0.id) }
            guard !members.isEmpty else { return nil }
            let center = members.map(\.anchor).reduce(.zero, +) / Float(members.count)
            // Member roof points let the area caption stay with a visible part of the compound.
            return Self(id: group.id, title: group.name, anchor: center + SIMD3(0, 5, 0), roof: members.map(\.anchor))
        }
    }
}

enum CampusMapLabelLayout {
    enum Level { case areas, buildings }
    struct Candidate {
        let id: String
        let frame: CGRect
        var alternatives: [CGRect] = []
    }

    /// Screen density rather than raw pinch scale works on different viewport sizes.
    /// Separate enter/exit thresholds avoid flicker during small pinch movements.
    static func level(pixelsPerUnit: CGFloat, previous: Level) -> Level {
        switch previous {
        case .areas: return pixelsPerUnit >= 6.5 ? .buildings : .areas
        case .buildings: return pixelsPerUnit <= 5.3 ? .areas : .buildings
        }
    }

    static func canNameBuilding(footprint: CGRect) -> Bool {
        !footprint.isNull && footprint.width.isFinite && footprint.height.isFinite
            && max(footprint.width, footprint.height) >= 56
            && min(footprint.width, footprint.height) >= 16
            && footprint.width * footprint.height >= 1_100
    }

    /// Candidates arrive in stable priority order; never shift a name onto another building.
    static func placements(_ candidates: [Candidate], viewport: CGRect, obstacles: [CGRect]) -> [String: CGRect] {
        guard viewport.width > 0, viewport.height > 0 else { return [:] }
        var occupied = obstacles.map { $0.insetBy(dx: -4, dy: -4) }
        var result: [String: CGRect] = [:]
        for candidate in candidates {
            for option in [candidate.frame] + candidate.alternatives {
                let frame = option.insetBy(dx: -4, dy: -3)
                guard frame.origin.x.isFinite, frame.origin.y.isFinite, frame.width.isFinite, frame.height.isFinite,
                      viewport.contains(frame), !occupied.contains(where: { $0.intersects(frame) }) else { continue }
                result[candidate.id] = option; occupied.append(frame)
                break
            }
        }
        return result
    }
}
