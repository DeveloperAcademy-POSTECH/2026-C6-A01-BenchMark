//
//  CampusEducationSite.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import simd

/// Display parcel fitted to the official aerial plan. X east, Z south, 0.12 units/m.
/// This replaces Posville 6 and the parking surface, not the library, C5 or the road.
enum CampusEducationSite {
    static let retiredBuildingID = "136961801"
    static let libraryID = "136182168"
    static let c5ID = "397201294"
    static let center = SIMD3<Float>(52, 0.45, 41.1)
    static let heading: Float = 1.96
    // Uniform scale: the supplied model's gross footprint matches the published
    // 13,054.01 m² building area. About 136 × 121 × 42 m, not surveyed dimensions.
    static let scale: Float = 1.2795299
    static let bridgeAnchor = SIMD3<Float>(-6.3734664, 1.076984, -2.9537949)
    static let boundary: [SIMD2<Float>] = [
        [59.288, 43.332], [56.934, 47.409], [51.462, 50.568],
        [49.519, 50.568], [48.467, 49.961], [42.721, 40.008],
        [42.721, 38.070], [44.401, 35.160], [48.073, 33.040],
        [52.304, 33.040], [57.788, 36.207], [59.288, 38.804]
    ]
    private static let minimum = boundary.reduce(SIMD2<Float>(repeating: .greatestFiniteMagnitude), simd_min)
    private static let maximum = boundary.reduce(SIMD2<Float>(repeating: -.greatestFiniteMagnitude), simd_max)
    static let elevation: Float = 0.45

    static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }

    static func contains(_ p: SIMD3<Float>) -> Bool {
        let point = SIMD2(p.x, p.z)
        return boundary.indices.allSatisfy { i in
            let a = boundary[i], b = boundary[(i + 1) % boundary.count]
            return cross(b - a, point - a) >= -0.00001
        }
    }

    static func world(_ local: SIMD3<Float>) -> SIMD3<Float> {
        center + simd_quatf(angle: heading, axis: [0, 1, 0]).act(local * scale)
    }

    static func local(_ world: SIMD3<Float>) -> SIMD3<Float> {
        simd_quatf(angle: -heading, axis: [0, 1, 0]).act(world - center) / scale
    }

    /// Extend the web's -X gallery straight to the library's actual footprint edge.
    static func libraryLanding(data: CampusMapData) -> SIMD3<Float>? {
        guard let library = data.buildings.first(where: { $0.id == libraryID }) else { return nil }
        let start = world(bridgeAnchor)
        let axis = simd_quatf(angle: heading, axis: [0, 1, 0]).act(SIMD3<Float>(-1, 0, 0))
        let origin = SIMD2(start.x, start.z), direction = SIMD2(axis.x, axis.z)
        var distance: Float?
        for i in library.p.indices {
            let p = library.p[i], q = library.p[(i + 1) % library.p.count]
            let a = SIMD2(Float(p[0]), Float(-p[1])), b = SIMD2(Float(q[0]), Float(-q[1]))
            let edge = b - a, denominator = cross(direction, edge)
            guard abs(denominator) > 0.00001 else { continue }
            let t = cross(a - origin, edge) / denominator
            let u = cross(a - origin, direction) / denominator
            if t >= 0, u >= 0, u <= 1 { distance = min(distance ?? t, t) }
        }
        guard let distance, distance < 4 else { return nil }
        return start + axis * (distance + 0.03)
    }

    struct MeshBuffers {
        var positions: [SIMD3<Float>]
        var normals: [SIMD3<Float>]
        var indices: [UInt32]
    }

    struct Tree {
        let center: SIMD2<Float>
        var removed: Bool {
            // Include the crown radius so the cleared parcel has no overhanging scraps.
            boundary.indices.allSatisfy { i in
                let a = boundary[i], edge = boundary[(i + 1) % boundary.count] - a
                return cross(edge, center - a) >= -0.65 * simd_length(edge)
            }
        }
    }

    static func trees(in trunks: MeshBuffers) -> [Tree] {
        components(trunks).map { ids in Tree(center: componentCenter(ids, in: trunks)) }
            .filter { $0.center.x > minimum.x - 2 && $0.center.x < maximum.x + 2 &&
                      $0.center.y > minimum.y - 2 && $0.center.y < maximum.y + 2 }
    }

    /// Tree crowns and trunks occupy separate material tiles. Associate each complete
    /// component with its trunk rather than slicing leaves at the parcel boundary.
    static func clearingVegetation(_ source: MeshBuffers, trees: [Tree]) -> MeshBuffers {
        guard !trees.isEmpty else { return source }
        var removed = Set<UInt32>()
        for ids in components(source) {
            let center = componentCenter(ids, in: source)
            guard let tree = trees.min(by: { simd_distance_squared($0.center, center) < simd_distance_squared($1.center, center) }),
                  simd_distance(tree.center, center) < 0.9, tree.removed else { continue }
            removed.formUnion(ids)
        }
        return MeshBuffers(positions: source.positions, normals: source.normals,
                           indices: source.indices.filter { !removed.contains($0) })
    }

    private static func componentCenter(_ ids: [UInt32], in source: MeshBuffers) -> SIMD2<Float> {
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for id in ids {
            let p = source.positions[Int(id)], point = SIMD2(p.x, p.z)
            lo = simd_min(lo, point); hi = simd_max(hi, point)
        }
        return (lo + hi) / 2
    }

    private static func components(_ source: MeshBuffers) -> [[UInt32]] {
        var parent = Array(source.positions.indices)
        func root(_ index: Int) -> Int {
            var i = index
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        // Flat-shaded foliage has duplicated vertices at normal seams.
        var welded: [SIMD3<Int32>: Int] = [:]
        for (i, p) in source.positions.enumerated() {
            let key = SIMD3<Int32>(Int32((p.x * 10_000).rounded()), Int32((p.y * 10_000).rounded()), Int32((p.z * 10_000).rounded()))
            if let prior = welded[key] { parent[root(i)] = root(prior) } else { welded[key] = i }
        }
        for i in stride(from: 0, to: source.indices.count, by: 3) {
            let a = Int(source.indices[i]), b = Int(source.indices[i + 1]), c = Int(source.indices[i + 2])
            parent[root(a)] = root(b); parent[root(a)] = root(c)
        }
        var groups: [Int: [UInt32]] = [:]
        for id in Set(source.indices) { groups[root(Int(id)), default: []].append(id) }
        return Array(groups.values)
    }

    private struct Vertex {
        var p: SIMD3<Float>
        var n: SIMD3<Float>
    }

    /// Subtract a convex parcel from every intersecting triangle, including ground,
    /// foundations, vertical walls and roofs. Centroid-only deletion left wall fragments.
    /// Outside portions retain their interpolated normals; adjacent buildings are intact.
    static func clearing(_ source: MeshBuffers) -> MeshBuffers {
        guard !source.positions.allSatisfy({ $0.x < minimum.x }), !source.positions.allSatisfy({ $0.x > maximum.x }),
              !source.positions.allSatisfy({ $0.z < minimum.y }), !source.positions.allSatisfy({ $0.z > maximum.y }) else { return source }
        var result = MeshBuffers(positions: source.positions, normals: source.normals, indices: [])
        result.indices.reserveCapacity(source.indices.count)
        for i in stride(from: 0, to: source.indices.count, by: 3) {
            let ids = Array(source.indices[i..<i + 3])
            let triangle = ids.map { Vertex(p: source.positions[Int($0)], n: source.normals[Int($0)]) }
            if triangle.allSatisfy({ $0.p.x < minimum.x }) || triangle.allSatisfy({ $0.p.x > maximum.x }) ||
                triangle.allSatisfy({ $0.p.z < minimum.y }) || triangle.allSatisfy({ $0.p.z > maximum.y }) {
                result.indices += ids; continue
            }
            // A separating edge means the complete triangle is outside the parcel.
            if boundary.indices.contains(where: { edge in
                let a = boundary[edge], b = boundary[(edge + 1) % boundary.count]
                return triangle.allSatisfy { cross(b - a, SIMD2($0.p.x, $0.p.z) - a) < 0 }
            }) { result.indices += ids; continue }
            var remaining = triangle
            for edge in boundary.indices {
                guard remaining.count >= 3 else { break }
                let a = boundary[edge], b = boundary[(edge + 1) % boundary.count]
                var inside: [Vertex] = [], outside: [Vertex] = []
                for k in remaining.indices {
                    let u = remaining[k], v = remaining[(k + 1) % remaining.count]
                    let du = cross(b - a, SIMD2(u.p.x, u.p.z) - a)
                    let dv = cross(b - a, SIMD2(v.p.x, v.p.z) - a)
                    if du >= 0 { inside.append(u) } else { outside.append(u) }
                    if (du >= 0) != (dv >= 0) {
                        let t = du / (du - dv), normal = u.n + (v.n - u.n) * t
                        let cut = Vertex(p: u.p + (v.p - u.p) * t,
                                         n: simd_length_squared(normal) > 0.00001 ? simd_normalize(normal) : u.n)
                        inside.append(cut); outside.append(cut)
                    }
                }
                if outside.count >= 3 {
                    for k in 1..<outside.count - 1 {
                        let vertices = [outside[0], outside[k], outside[k + 1]]
                        guard simd_length_squared(simd_cross(vertices[1].p - vertices[0].p, vertices[2].p - vertices[0].p)) > 0.0000000001 else { continue }
                        let first = UInt32(result.positions.count)
                        result.positions += vertices.map(\.p)
                        result.normals += vertices.map(\.n)
                        result.indices += [first, first + 1, first + 2]
                    }
                }
                remaining = inside
            }
        }
        return result
    }
}
