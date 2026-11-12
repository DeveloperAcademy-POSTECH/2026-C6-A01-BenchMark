//
//  CampusEducationDistrict.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import RealityKit
import UIKit

/// The web's assembled geometry, with a single rigid campus placement.
@MainActor enum CampusEducationDistrict {
    static let retiredBuildingID = CampusEducationSite.retiredBuildingID
    static let center = CampusEducationSite.center
    static let heading = CampusEducationSite.heading
    static let scale = CampusEducationSite.scale
    static let officialURL = URL(string: "https://www.postech.ac.kr/kor/innovation/education_district_cp.do")!
    static let farCount = 24_000
    static let nearCount = 96_000
    private static var meshes: (far: MeshResource, near: MeshResource)?

    struct Sample {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let brightness: Float
    }
    struct Geometry {
        let points: [Sample]
        let shell: [SIMD3<Float>]
        let groundOffset: Float
    }

    static func geometry() throws -> Geometry {
        guard let url = Bundle.main.url(forResource: "education-district-points", withExtension: "bin") else { throw CocoaError(.fileNoSuchFile) }
        let bytes = try Data(contentsOf: url)
        guard bytes.count >= 20, bytes.prefix(8) == Data("OIEDU002".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        return try bytes.withUnsafeBytes { buffer in
            func uint(_ offset: Int) -> UInt32 { UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
            func float(_ offset: Int) -> Float { Float(bitPattern: uint(offset)) }
            func vector(_ offset: Int) -> SIMD3<Float> { [float(offset), float(offset + 4), float(offset + 8)] }
            let count = Int(uint(8)), shellCount = Int(uint(12)), ground = float(16)
            guard count == nearCount, shellCount > 0, shellCount < 500_000, shellCount % 3 == 0,
                  bytes.count == 20 + count * 28 + shellCount * 12, ground.isFinite else { throw CocoaError(.fileReadCorruptFile) }
            let points = (0..<count).map { i in
                Sample(position: vector(20 + i * 28), normal: vector(32 + i * 28), brightness: float(44 + i * 28))
            }
            let shell = (0..<shellCount).map { vector(20 + count * 28 + $0 * 12) }
            func finite(_ p: SIMD3<Float>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
            guard points.allSatisfy({ finite($0.position) && finite($0.normal) && $0.brightness.isFinite }), shell.allSatisfy(finite) else { throw CocoaError(.fileReadCorruptFile) }
            return Geometry(points: points, shell: shell, groundOffset: ground)
        }
    }

    static func makeEntity(data: CampusMapData) throws -> ModelEntity {
        if meshes == nil {
            let source = try geometry()
            // Prefixes are the web's spatially interleaved tiers. Striding loses rows.
            meshes = (try pearls(Array(source.points.prefix(farCount)), radius: 0.036, ground: source.groundOffset),
                      try pearls(source.points, radius: 0.023, ground: source.groundOffset))
        }
        let model = ModelEntity(mesh: meshes!.far, materials: materials)
        model.name = "campus.education-district"
        model.position = center
        model.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
        model.scale = SIMD3(repeating: scale)
        model.components.set(DynamicLightShadowComponent(castsShadow: false))
        // Only the web's surface pearls form the building. Do not add a solid
        // backing or an occlusion material: gaps must reveal the surrounding map.
        model.addChild(try siteSurface(data: data))
        if let landing = CampusEducationSite.libraryLanding(data: data) {
            model.addChild(try bridge(to: CampusEducationSite.local(landing)))
        }
        // One selection volume, not a collider or entity for each pearl.
        model.collision = CollisionComponent(shapes: [.generateBox(size: [12.8, 4.6, 8.4]).offsetBy(translation: [0, 2.3, 0])], mode: .default, filter: .default)
        return model
    }

    static func update(_ entity: ModelEntity, near: Bool) {
        guard let meshes else { return }
        let desired = near ? meshes.near : meshes.far
        if entity.model?.mesh !== desired { entity.model?.mesh = desired }
    }

    private static var materials: [any Material] {
        // Keep every pearl white, including glazing. Emission provides a light
        // floor on the unlit side; the lit component retains each pearl's form.
        // The web's brightness tiers only accent louvres / terrace edges. This
        // does not add lights, bloom, backing geometry or transparent layers.
        [0.84, 0.875, 0.91, 0.945, 0.975, 1.0].map { value in
            let white = UIColor(red: value * 0.98, green: value * 0.99, blue: value, alpha: 1)
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: white)
            material.roughness = 0.62
            material.metallic = 0.0
            material.specular = 0.25
            material.emissiveColor = .init(color: white)
            material.emissiveIntensity = Float(0.35 + (value - 0.84) / 0.16 * 0.35)
            return material
        }
    }

    /// Smooth normals on eight triangles per sphere: 768k triangles for all 96k dots,
    /// no per-frame position uploads, entities, animation or transparency sorting.
    private static func pearls(_ points: [Sample], radius: Float, ground: Float = 0) throws -> MeshResource {
        let unit: [SIMD3<Float>] = [[0,1,0], [1,0,0], [0,0,1], [-1,0,0], [0,0,-1], [0,-1,0]]
        let faces: [UInt32] = [0,2,1, 0,3,2, 0,4,3, 0,1,4, 5,1,2, 5,2,3, 5,3,4, 5,4,1]
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = [], materialIDs: [UInt32] = []
        positions.reserveCapacity(points.count * 6); normals.reserveCapacity(points.count * 6)
        indices.reserveCapacity(points.count * 24); materialIDs.reserveCapacity(points.count * 8)
        for point in points {
            let base = point.position + SIMD3(0, ground, 0) + point.normal * 0.012
            let index = UInt32(positions.count)
            for v in unit { positions.append(base + v * radius); normals.append(v) }
            for f in faces { indices.append(f + index) }
            let shade = UInt32(max(0, min(5, Int(((point.brightness - 0.55) / 0.45 * 5).rounded()))))
            materialIDs += Array(repeating: shade, count: 8)
        }
        var descriptor = MeshDescriptor(name: "Education web surface pearls \(points.count)")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(materialIDs)
        return try MeshResource.generate(from: [descriptor])
    }

    private static func parcelMesh(_ points: [SIMD3<Float>]) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "Education cleared parcel surface")
        descriptor.positions = MeshBuffers.Positions(points)
        descriptor.primitives = .triangles((0..<UInt32(points.count)).map { $0 })
        return try MeshResource.generate(from: [descriptor])
    }

    private static func siteSurface(data: CampusMapData) throws -> ModelEntity {
        // A continuous flat paved parcel with retaining sides, replacing the old
        // parking/terrain triangles. It stops short of C5, library and the road.
        let top = CampusEducationSite.boundary.map { CampusEducationSite.local([$0.x, CampusEducationSite.elevation, $0.y]) }
        var vertices: [SIMD3<Float>] = []
        for i in 1..<top.count - 1 { vertices += [top[0], top[i + 1], top[i]] }
        for i in CampusEducationSite.boundary.indices {
            let a = CampusEducationSite.boundary[i], b = CampusEducationSite.boundary[(i + 1) % top.count]
            let steps = max(1, Int(ceil(simd_distance(a, b) / 0.12)))
            for step in 0..<steps {
                let u = a + (b - a) * Float(step) / Float(steps)
                let v = a + (b - a) * Float(step + 1) / Float(steps)
                let hu = data.surface?.height(x: u.x, z: u.y) ?? CampusEducationSite.elevation
                let hv = data.surface?.height(x: v.x, z: v.y) ?? CampusEducationSite.elevation
                let p = CampusEducationSite.local([u.x, max(hu, CampusEducationSite.elevation) + 0.025, u.y])
                let q = CampusEducationSite.local([v.x, max(hv, CampusEducationSite.elevation) + 0.025, v.y])
                // Follow the original terrain at the cut edge, including the uphill
                // Posville foundation. Double-sided retaining faces close that gap.
                // Overlap the coarse height-field sample to avoid hairline cracks.
                let r = CampusEducationSite.local([v.x, min(hv, CampusEducationSite.elevation) - 0.15, v.y])
                let s = CampusEducationSite.local([u.x, min(hu, CampusEducationSite.elevation) - 0.15, u.y])
                vertices += [p,q,r, p,r,s]
            }
        }
        var material = SimpleMaterial(color: UIColor(red: 0.75, green: 0.77, blue: 0.76, alpha: 1), roughness: 1, isMetallic: false)
        material.faceCulling = .none
        let surface = ModelEntity(mesh: try parcelMesh(vertices), materials: [material])
        surface.name = "education.cleared-parcel"
        return surface
    }

    private static func bridge(to end: SIMD3<Float>) throws -> Entity {
        let x0 = end.x, x1: Float = -6.20, z0: Float = -0.5, z1: Float = 0.13
        let y0: Float = 1.33, y1: Float = 1.66
        var points: [Sample] = []
        let columns = max(2, Int(ceil((x1 - x0) / 0.045)))
        for i in 0...columns {
            let x = x0 + (x1 - x0) * Float(i) / Float(columns)
            for j in 0...14 {
                let z = z0 + (z1 - z0) * Float(j) / 14
                points.append(Sample(position: [x, y0, z], normal: [0,-1,0], brightness: 0.8))
                points.append(Sample(position: [x, y1, z], normal: [0,1,0], brightness: 0.9))
            }
            for j in 0...7 {
                let y = y0 + (y1 - y0) * Float(j) / 7
                points.append(Sample(position: [x,y,z0], normal: [0,0,-1], brightness: j == 0 || j == 7 ? 1 : 0.6))
                points.append(Sample(position: [x,y,z1], normal: [0,0,1], brightness: j == 0 || j == 7 ? 1 : 0.6))
            }
        }
        let gallery = ModelEntity(mesh: try pearls(points, radius: 0.026), materials: materials)
        gallery.name = "education.library-connector"
        gallery.components.set(DynamicLightShadowComponent(castsShadow: false))
        return gallery
    }
}
