//
//  CampusEducationLandscape.swift
//  OiDonation
//
//  Created by Codex on 2026/11/13.
//

import simd

/// Replace the former parking slabs and their two access spurs with one grass
/// surface. The main road, other paths and neighboring foundations are cutouts.
struct CampusEducationLandscape {
    typealias Buffers = CampusEducationSite.MeshBuffers
    static let boundary: [SIMD2<Float>] = [
        [52,28.8], [55.9521,30.7484], [59.7106,38.8984], [63.416,46.984],
        [50.628,52.691], [44.5,51], [38.5,44], [38.3,36], [42,30]
    ]
    private static let outline = Region(boundary)
    private let protected: [Region]
    private let protectedAsphalt: [Region]

    init(data: CampusMapData) {
        let grading = CampusEducationSite.TerrainGrading(data: data)
        let roadRegions = grading.roads.map { road in
            let ends = [road.a, road.b]
            // Circumscribed octagon includes the entire road/curb radius.
            let radius = road.radius / cos(Float.pi / 8)
            return Region(Self.hull(ends.flatMap { p in
                (0..<8).map { i in
                    let angle = Float(i) * .pi / 4
                    return p + SIMD2(cos(angle), sin(angle)) * radius
                }
            }))
        }
        let foundations = grading.foundations.map { Region(Self.hull($0)) }
        protected = roadRegions + foundations
        // An access spur crossing a footpath must not leave a gray asphalt bar
        // inside the footpath's protected strip. The actual path tile stays intact.
        protectedAsphalt = zip(grading.roads, roadRegions).compactMap { $0.footpath ? nil : $1 } + foundations
    }

    static func boundaryDistance(_ p: SIMD2<Float>) -> Float {
        guard outline.contains(p) else { return 0 }
        return boundary.indices.reduce(Float.greatestFiniteMagnitude) { distance, i in
            min(distance, CampusEducationSite.TerrainGrading.segmentDistance(p, boundary[i], boundary[(i + 1) % boundary.count]))
        }
    }

    func contains(_ p: SIMD2<Float>) -> Bool {
        Self.outline.contains(p) && !protected.contains { $0.contains(p) }
    }

    /// Only the part inside the restoration boundary and outside every protected
    /// road/foundation is removed. Intersections are clipped, not centroid-tested.
    func clearing(_ source: Buffers, preservingFootpaths: Bool = true) -> Buffers {
        guard Self.outline.overlaps(source.positions.map { SIMD2($0.x,$0.z) }) else { return source }
        var result = Buffers(positions: source.positions, normals: source.normals, indices: [])
        result.indices.reserveCapacity(source.indices.count)
        for i in stride(from: 0, to: source.indices.count, by: 3) {
            let ids = Array(source.indices[i..<i+3])
            let triangle = ids.map { Vertex(p: source.positions[Int($0)], n: source.normals[Int($0)]) }
            guard Self.outline.overlaps(triangle.map(\.xz)) else { result.indices += ids; continue }
            let pieces = partition(triangle, preserving: preservingFootpaths ? protected : protectedAsphalt)
            if pieces.replaced.isEmpty { result.indices += ids; continue }
            for polygon in pieces.kept { Self.append(polygon, to: &result) }
        }
        return result
    }

    /// The old asphalt occupied the crossings, so the exported footpath tiles
    /// have gaps there. Reuse only those crossing faces in the footpath material.
    func pathCrossings(_ asphalt: Buffers) -> Buffers {
        var result = Buffers(positions: [], normals: [], indices: [])
        guard Self.outline.overlaps(asphalt.positions.map { SIMD2($0.x,$0.z) }) else { return result }
        for i in stride(from:0,to:asphalt.indices.count,by:3) {
            let triangle = asphalt.indices[i..<i+3].map { Vertex(p:asphalt.positions[Int($0)],n:asphalt.normals[Int($0)]) }
            for removed in partition(triangle,preserving:protectedAsphalt).replaced {
                for crossing in partition(removed,preserving:protected).kept { Self.append(crossing,to:&result) }
            }
        }
        return result
    }

    /// A shared, 2m grid replaces coarse displaced parking triangles. Only a
    /// surface is generated; it has no vertical skirts or underground solid fill.
    func grass(surface: CampusHeightField) -> Buffers {
        var result = Buffers(positions: [], normals: [], indices: [])
        let step: Float = 0.24
        let lo = Self.outline.minimum, hi = Self.outline.maximum
        let nx = Int(ceil((hi.x-lo.x)/step)), nz = Int(ceil((hi.y-lo.y)/step))
        for z in 0..<nz {
            for x in 0..<nx {
                let x0 = lo.x + Float(x)*step, x1 = min(hi.x,x0+step)
                let z0 = lo.y + Float(z)*step, z1 = min(hi.y,z0+step)
                // Clockwise in X/Z gives upward-facing triangles in world space.
                let cell: [Vertex] = [[x0,0,z0],[x0,0,z1],[x1,0,z1],[x1,0,z0]].map { Vertex(p:$0,n:[0,1,0]) }
                for polygon in partition(cell, preserving: protected).replaced { Self.append(polygon, to: &result) }
            }
        }
        // Weld grid seams and clipped boundary vertices before computing normals.
        // One compact mesh joins an existing grass tile, sharing its exact palette.
        var compact = Buffers(positions: [], normals: [], indices: [])
        var vertices: [SIMD2<Int32>: UInt32] = [:]
        for id in result.indices {
            let p = result.positions[Int(id)]
            let key = SIMD2<Int32>(Int32((p.x*10_000).rounded()), Int32((p.z*10_000).rounded()))
            if let existing = vertices[key] { compact.indices.append(existing); continue }
            let index = UInt32(compact.positions.count)
            vertices[key] = index
            let y = surface.groundHeight(x:p.x,z:p.z) ?? CampusEducationSite.elevation
            let delta: Float = 0.12
            let dx = (surface.groundHeight(x:p.x+delta,z:p.z) ?? y) - (surface.groundHeight(x:p.x-delta,z:p.z) ?? y)
            let dz = (surface.groundHeight(x:p.x,z:p.z+delta) ?? y) - (surface.groundHeight(x:p.x,z:p.z-delta) ?? y)
            compact.positions.append([p.x,y,p.z])
            compact.normals.append(simd_normalize([-dx,2*delta,-dz]))
            compact.indices.append(index)
        }
        // Clipping and welding can collapse microscopic boundary slivers. Drop
        // them after welding so no inverted/zero-area triangles reach the GPU.
        compact.indices = stride(from:0,to:compact.indices.count,by:3).flatMap { i -> [UInt32] in
            let ids = Array(compact.indices[i..<i+3])
            let a = compact.positions[Int(ids[0])], b = compact.positions[Int(ids[1])], c = compact.positions[Int(ids[2])]
            return simd_cross(b-a,c-a).y > 1e-9 ? ids : []
        }
        return compact
    }

    private struct Vertex {
        var p: SIMD3<Float>
        var n: SIMD3<Float>
        var xz: SIMD2<Float> { [p.x,p.z] }
    }

    private struct Region {
        let points: [SIMD2<Float>]
        let minimum: SIMD2<Float>
        let maximum: SIMD2<Float>
        init(_ points: [SIMD2<Float>]) {
            self.points = points
            minimum = points.reduce(SIMD2(repeating: Float.greatestFiniteMagnitude), simd_min)
            maximum = points.reduce(SIMD2(repeating: -Float.greatestFiniteMagnitude), simd_max)
        }
        func contains(_ p: SIMD2<Float>) -> Bool {
            points.indices.allSatisfy { i in
                CampusEducationSite.cross(points[(i+1)%points.count]-points[i],p-points[i]) >= -0.00001
            }
        }
        func overlaps(_ vertices: [SIMD2<Float>]) -> Bool {
            !vertices.isEmpty && !vertices.allSatisfy { $0.x < minimum.x } && !vertices.allSatisfy { $0.x > maximum.x }
                && !vertices.allSatisfy { $0.y < minimum.y } && !vertices.allSatisfy { $0.y > maximum.y }
        }
    }

    private func partition(_ polygon: [Vertex], preserving regions: [Region]) -> (kept: [[Vertex]], replaced: [[Vertex]]) {
        let outer = Self.split(polygon, by: Self.outline)
        var kept = outer.outside
        var remaining = outer.inside.count >= 3 ? [outer.inside] : []
        for region in regions where region.overlaps(polygon.map(\.xz)) {
            var next: [[Vertex]] = []
            for piece in remaining {
                let split = Self.split(piece, by: region)
                if split.inside.count >= 3 { kept.append(split.inside) }
                next += split.outside
            }
            remaining = next
            if remaining.isEmpty { break }
        }
        return (kept,remaining)
    }

    private static func split(_ polygon: [Vertex], by region: Region) -> (inside: [Vertex], outside: [[Vertex]]) {
        guard region.overlaps(polygon.map(\.xz)) else { return ([],[polygon]) }
        var remaining = polygon, result: [[Vertex]] = []
        for i in region.points.indices {
            guard remaining.count >= 3 else { break }
            let a = region.points[i], edge = region.points[(i+1)%region.points.count]-a
            var inside: [Vertex] = [], outside: [Vertex] = []
            for j in remaining.indices {
                let u = remaining[j], v = remaining[(j+1)%remaining.count]
                let du = CampusEducationSite.cross(edge,u.xz-a), dv = CampusEducationSite.cross(edge,v.xz-a)
                if du >= 0 { inside.append(u) } else { outside.append(u) }
                if (du >= 0) != (dv >= 0) {
                    let t = du/(du-dv)
                    let cut = Vertex(p:u.p+(v.p-u.p)*t,n:u.n+(v.n-u.n)*t)
                    inside.append(cut); outside.append(cut)
                }
            }
            if outside.count >= 3 { result.append(outside) }
            remaining = inside
        }
        return (remaining,result)
    }

    private static func append(_ polygon: [Vertex], to mesh: inout Buffers) {
        guard polygon.count >= 3 else { return }
        for i in 1..<polygon.count-1 {
            let t = [polygon[0],polygon[i],polygon[i+1]]
            guard simd_length_squared(simd_cross(t[1].p-t[0].p,t[2].p-t[0].p)) > 1e-12 else { continue }
            let start = UInt32(mesh.positions.count)
            mesh.positions += t.map(\.p); mesh.normals += t.map(\.n)
            mesh.indices += [start,start+1,start+2]
        }
    }

    private static func hull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let sorted = Array(Set(points)).sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func chain(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
            var result: [SIMD2<Float>] = []
            for p in points {
                while result.count >= 2, CampusEducationSite.cross(result.last!-result[result.count-2],p-result.last!) <= 0 { result.removeLast() }
                result.append(p)
            }
            return Array(result.dropLast())
        }
        return chain(sorted) + chain(sorted.reversed())
    }
}
