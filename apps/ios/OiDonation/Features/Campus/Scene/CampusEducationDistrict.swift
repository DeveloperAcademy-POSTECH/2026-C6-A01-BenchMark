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
    nonisolated static let farCount = 37_282
    nonisolated static let nearCount = 62_107
    nonisolated static let totalCount = 110_869
    enum Detail: Sendable { case far, near }
    private static var meshes: [Detail: MeshResource] = [:]
    private static var preparation: [Detail: Task<MeshResource, Error>] = [:]

    nonisolated struct Sample: Sendable {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let brightness: Float
    }
    nonisolated struct Geometry: Sendable {
        let points: [Sample]
        let shell: [SIMD3<Float>]
        let groundOffset: Float
    }

    nonisolated static func geometry() throws -> Geometry {
        guard let url = Bundle.main.url(forResource: "education-district-points", withExtension: "bin") else { throw CocoaError(.fileNoSuchFile) }
        let bytes = try Data(contentsOf: url)
        guard bytes.count >= 20, bytes.prefix(8) == Data("OIEDU002".utf8) else { throw CocoaError(.fileReadCorruptFile) }
        return try bytes.withUnsafeBytes { buffer in
            func uint(_ offset: Int) -> UInt32 { UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
            func float(_ offset: Int) -> Float { Float(bitPattern: uint(offset)) }
            func vector(_ offset: Int) -> SIMD3<Float> { [float(offset), float(offset + 4), float(offset + 8)] }
            let count = Int(uint(8)), shellCount = Int(uint(12)), ground = float(16)
            guard count == totalCount, shellCount > 0, shellCount < 500_000, shellCount % 3 == 0,
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

    static func preparedMesh(_ detail: Detail) -> MeshResource? { meshes[detail] }

    static func prepare(_ detail: Detail) async throws -> MeshResource {
        if let mesh = meshes[detail] { return mesh }
        if let pending = preparation[detail] { return try await pending.value }
        let count = detail == .near ? nearCount : farCount
        let radius: Float = detail == .near ? 0.025 : 0.031
        let task = Task { @MainActor in
            defer { preparation[detail] = nil }
            let descriptor = try await Task.detached(priority: .userInitiated) {
                let source = try geometry()
                return pearlDescriptor(Array(source.points.prefix(count)), radius: radius, ground: source.groundOffset)
            }.value
            let mesh = try await MeshResource(from: [descriptor])
            meshes[detail] = mesh
            return mesh
        }
        preparation[detail] = task
        return try await task.value
    }

    static func makeEntity(data: CampusMapData) throws -> ModelEntity {
        guard let mesh = meshes[.far] else { throw CocoaError(.fileReadCorruptFile) }
        let model = ModelEntity(mesh: mesh, materials: materials)
        model.name = "campus.education-district"
        model.position = center
        model.orientation = simd_quatf(angle: heading, axis: [0, 1, 0])
        model.scale = SIMD3(repeating: scale)
        model.components.set(DynamicLightShadowComponent(castsShadow: false))
        // Only the web's surface pearls form the building. Do not add a solid
        // backing or an occlusion material: gaps must reveal the surrounding map.
        if let landing = CampusEducationSite.libraryLanding(data: data) {
            model.addChild(try bridge(to: CampusEducationSite.local(landing)))
        }
        // One selection volume, not a collider or entity for each pearl.
        let bounds = model.visualBounds(recursive: false, relativeTo: model)
        model.collision = CollisionComponent(shapes: [.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)], mode: .default, filter: .default)
        return model
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

    /// Smooth normals on eight triangles per sphere: 497k triangles for the near 62k tier,
    /// no per-frame position uploads, entities, animation or transparency sorting.
    private static func pearls(_ points: [Sample], radius: Float, ground: Float = 0) throws -> MeshResource {
        return try MeshResource.generate(from: [pearlDescriptor(points, radius: radius, ground: ground)])
    }

    nonisolated private static func pearlDescriptor(_ points: [Sample], radius: Float, ground: Float) -> MeshDescriptor {
        let unit: [SIMD3<Float>] = [[0,1,0], [1,0,0], [0,0,1], [-1,0,0], [0,0,-1], [0,-1,0]]
        let faces: [UInt32] = [0,2,1, 0,3,2, 0,4,3, 0,1,4, 5,1,2, 5,2,3, 5,3,4, 5,4,1]
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = [], materialIDs: [UInt32] = []
        positions.reserveCapacity(points.count * 6); normals.reserveCapacity(points.count * 6)
        indices.reserveCapacity(points.count * 24); materialIDs.reserveCapacity(points.count * 8)
        for point in points {
            let base = point.position + SIMD3(0, ground, 0)
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
        return descriptor
    }

    private static func bridge(to end: SIMD3<Float>) throws -> Entity {
        let anchor = CampusEducationSite.bridgeAnchor
        let x0 = end.x, x1 = anchor.x + 0.08, z0 = anchor.z - 0.57, z1 = anchor.z + 0.57
        let y0 = anchor.y - 0.18, y1 = anchor.y + 0.18
        var points: [Sample] = []
        let columns = max(2, Int(ceil((x1 - x0) / 0.059143)))
        for i in 0...columns {
            let x = x0 + (x1 - x0) * Float(i) / Float(columns)
            for j in 0...20 {
                let z = z0 + (z1 - z0) * Float(j) / 20
                points.append(Sample(position: [x, y0, z], normal: [0,-1,0], brightness: 0.8))
                points.append(Sample(position: [x, y1, z], normal: [0,1,0], brightness: 0.9))
            }
            for j in 1..<6 {
                let y = y0 + (y1 - y0) * Float(j) / 6
                points.append(Sample(position: [x,y,z0], normal: [0,0,-1], brightness: 0.75))
                points.append(Sample(position: [x,y,z1], normal: [0,0,1], brightness: 0.75))
            }
        }
        let gallery = ModelEntity(mesh: try pearls(points, radius: 0.025), materials: materials)
        gallery.name = "education.library-connector"
        gallery.components.set(DynamicLightShadowComponent(castsShadow: false))
        return gallery
    }
}
