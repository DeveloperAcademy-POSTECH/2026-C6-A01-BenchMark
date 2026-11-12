//
//  OiSeedCucumberModel.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/12/26.
//

import CoreGraphics
import Foundation
import RealityKit
import simd

enum OiSeedCucumberGarment: String, CaseIterable {
    case whiteTshirt = "SeedCucumberWhiteTshirt"
    case longPants = "SeedCucumberLongPants"

    var title: String {
        switch self {
        case .whiteTshirt: OiWardrobeLook.Top.tshirt.title
        case .longPants: OiWardrobeLook.Bottom.long.title
        }
    }
}

@MainActor enum OiSeedCucumberModel {
    private static let bodyTransformName = "SeedCucumberBodyTransform"
    private static let metresPerPixel: Float = 0.001
    private static let pivot = OiSeedCucumberAppearance.bodyPivot
    private static let faceParts: [(String, OiSeedCucumberLayer)] = [
        ("LeftEye", .leftEye), ("RightEye", .rightEye), ("Mouth", .mouth)
    ]

    private enum AssetError: Error {
        case missingPart(String)
        case invalidMesh(String)
        case invalidSkinSurface
    }

    static func make(appearance: OiSeedCucumberAppearance) async throws -> Entity {
        let asset = try await Entity(contentsOf: resource("SeedCucumberMaster", suffix: "usdz"))
        try Task.checkCancellation()

        let root = Entity()
        root.name = "SeedCucumber"
        let sized = Entity()
        sized.name = bodyTransformName
        root.addChild(sized)
        sized.addChild(asset)

        let width = Float(appearance.bodyWidth)
        let scale = SIMD3(width, Float(appearance.bodyHeight), width)
        let bodyResized = scale.x != 1 || scale.y != 1
        let movedFaces = faceParts.filter { bodyResized || appearance.faceFrame($0.1) != $0.1.sourceFrame }
        if !movedFaces.isEmpty {
            let surface = try SkinSurface.load(from: resource("SeedCucumberSurface", suffix: "json"))
            for (name, layer) in movedFaces {
                try Task.checkCancellation()
                guard let face = asset.findEntity(named: name) else { throw AssetError.missingPart(name) }
                let originalFrame = layer.sourceFrame
                let editedFrame = appearance.faceFrame(layer)
                try deformMeshes(in: face, relativeTo: root) { position in
                    let original = sourcePoint(position)
                    let edited = CGPoint(
                        x: editedFrame.minX + (original.x - originalFrame.minX) * editedFrame.width / originalFrame.width,
                        y: editedFrame.minY + (original.y - originalFrame.minY) * editedFrame.height / originalFrame.height
                    )
                    // The artwork frame already includes body sizing. Undo it to sample
                    // the unscaled skin and keep each vertex's original depth offset.
                    let editedX = Float(pivot.x) + Float(edited.x - pivot.x) / scale.x
                    let editedY = Float(pivot.y) + Float(edited.y - pivot.y) / scale.y
                    let originalSkin = surface.sample(x: Float(original.x), y: Float(original.y))
                    let editedSkin = surface.sample(x: editedX, y: editedY)
                    let offset = position.z - originalSkin.depth * metresPerPixel
                    return SIMD3(
                        (editedSkin.x - Float(pivot.x)) * metresPerPixel,
                        (Float(pivot.y) - editedY) * metresPerPixel,
                        editedSkin.depth * metresPerPixel + offset / scale.z
                    )
                }
            }
        }
        if appearance.stemLength != 1 || appearance.stemAngle != 0 || bodyResized {
            guard let stem = asset.findEntity(named: "Stem") else { throw AssetError.missingPart("Stem") }
            let stemRootDepth = stem.convert(position: .zero, to: root).z
            try deformMeshes(in: stem, relativeTo: root) { position in
                let edited = appearance.stemPoint(for: sourcePoint(position))
                // Keep the authored root cross-section and let its attachment follow the body.
                return SIMD3(
                    Float(edited.x - pivot.x) * metresPerPixel / scale.x,
                    Float(pivot.y - edited.y) * metresPerPixel / scale.y,
                    stemRootDepth + (position.z - stemRootDepth) / scale.z
                )
            }
        }

        sized.scale = scale
        let floor = sized.visualBounds(relativeTo: root).min.y
        guard floor.isFinite else { throw AssetError.invalidMesh(asset.name) }
        sized.position.y = -floor
        try Task.checkCancellation()
        return root
    }

    static func loadGarment(_ garment: OiSeedCucumberGarment) async throws -> Entity {
        let asset = try await Entity(contentsOf: resource(garment.rawValue, suffix: "usdz"))
        try Task.checkCancellation()
        let bounds = asset.visualBounds(relativeTo: nil)
        guard bounds.extents.x.isFinite, bounds.extents.y.isFinite, bounds.extents.z.isFinite,
              bounds.extents.x > 0, bounds.extents.y > 0, bounds.extents.z > 0 else {
            throw AssetError.invalidMesh(garment.rawValue)
        }
        asset.name = garment.rawValue
        return asset
    }

    static func setGarment(_ garment: OiSeedCucumberGarment, asset: Entity?, on model: Entity) throws {
        guard let body = model.findEntity(named: bodyTransformName) else {
            throw AssetError.missingPart(bodyTransformName)
        }
        let mounted = body.children.first { $0.name == garment.rawValue }
        guard mounted !== asset else { return }
        mounted?.removeFromParent()
        // The garment is authored in the neutral body's coordinates and inherits its size and ground offset.
        if let asset { body.addChild(asset) }
    }

    private static func resource(_ name: String, suffix: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: suffix, subdirectory: "Characters")
            ?? Bundle.main.url(forResource: name, withExtension: suffix) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    private static func sourcePoint(_ position: SIMD3<Float>) -> CGPoint {
        CGPoint(x: pivot.x + CGFloat(position.x / metresPerPixel),
                y: pivot.y - CGFloat(position.y / metresPerPixel))
    }

    private static func deformMeshes(in role: Entity, relativeTo root: Entity,
                                     by deform: (SIMD3<Float>) -> SIMD3<Float>) throws {
        var hasMesh = false
        func visit(_ entity: Entity) throws {
            if var component = entity.components[ModelComponent.self] {
                try Task.checkCancellation()
                let mesh = component.mesh.contents
                let entityToRoot = entity.transformMatrix(relativeTo: root)
                var edited = MeshResource.Contents()
                guard !mesh.instances.isEmpty else { throw AssetError.invalidMesh(role.name) }
                for (index, instance) in mesh.instances.enumerated() {
                    guard let source = mesh.models[instance.model] else { throw AssetError.invalidMesh(role.name) }
                    let meshToRoot = entityToRoot * instance.transform
                    let rootToMesh = simd_inverse(meshToRoot)
                    let parts = source.parts.map { part in
                        deformedPart(part) { point in
                            let rootPoint = meshToRoot * SIMD4(point, 1)
                            let editedRootPoint = deform(SIMD3(rootPoint.x, rootPoint.y, rootPoint.z))
                            let editedMeshPoint = rootToMesh * SIMD4(editedRootPoint, 1)
                            return SIMD3(editedMeshPoint.x, editedMeshPoint.y, editedMeshPoint.z)
                        }
                    }
                    // Separate models let each instance deform in its own stage coordinates.
                    let modelID = "Edited\(index)"
                    edited.models.insert(.init(id: modelID, parts: parts))
                    edited.instances.insert(.init(id: instance.id, model: modelID, at: instance.transform))
                }
                component.mesh = try MeshResource.generate(from: edited)
                entity.components.set(component)
                hasMesh = true
            }
            for child in entity.children { try visit(child) }
        }
        try visit(role)
        guard hasMesh else { throw AssetError.invalidMesh(role.name) }
    }

    private static func deformedPart(_ original: MeshResource.Part,
                                     by deform: (SIMD3<Float>) -> SIMD3<Float>) -> MeshResource.Part {
        let positions = original.positions.elements
        var part = original
        part.positions = .init(positions.map(deform))
        // Transport the authored normal and tangent frames through the same local warp.
        // The mesh keeps its UVs, indices and material assignment.
        let step: Float = 0.0005
        let dx = SIMD3(step, 0, 0)
        let dy = SIMD3(0, step, 0)
        let dz = SIMD3(0, 0, step)
        let jacobians = positions.map { position in
            simd_float3x3(columns: (
                (deform(position + dx) - deform(position - dx)) / (2 * step),
                (deform(position + dy) - deform(position - dy)) / (2 * step),
                (deform(position + dz) - deform(position - dz)) / (2 * step)
            ))
        }
        part.normals = transformed(original.normals, by: jacobians) { simd_transpose(simd_inverse($0)) }
        part.tangents = transformed(original.tangents, by: jacobians) { $0 }
        part.bitangents = transformed(original.bitangents, by: jacobians) { $0 }
        return part
    }

    private static func transformed(_ buffer: MeshBuffer<SIMD3<Float>>?, by matrices: [simd_float3x3],
                                    using transform: (simd_float3x3) -> simd_float3x3) -> MeshBuffer<SIMD3<Float>>? {
        guard let buffer, buffer.rate == .vertex else { return nil }
        let directions = buffer.elements
        guard directions.count == matrices.count else { return nil }
        return .init(zip(directions, matrices).map { direction, matrix in
            let mapped = transform(matrix) * direction
            let lengthSquared = simd_length_squared(mapped)
            return lengthSquared.isFinite && lengthSquared > 0.000001 ? simd_normalize(mapped) : direction
        })
    }

    private struct SkinSurface: Decodable {
        let minY: Float
        let stepY: Float
        let columns: Int
        let rows: [[Float]]

        static func load(from url: URL) throws -> Self {
            let surface = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
            guard surface.stepY > 0, surface.columns >= 2, surface.rows.count >= 2,
                  surface.rows.allSatisfy({ $0.count == surface.columns + 2 && $0[1] >= $0[0] }) else {
                throw AssetError.invalidSkinSurface
            }
            return surface
        }

        func sample(x: Float, y: Float) -> (x: Float, depth: Float) {
            let row = min(max((y - minY) / stepY, 0), Float(rows.count - 1))
            let lower = Int(row)
            let upper = min(lower + 1, rows.count - 1)
            let weight = row - Float(lower)
            let first = rows[lower]
            let second = rows[upper]
            let left = interpolate(first[0], second[0], weight)
            let right = interpolate(first[1], second[1], weight)
            let center = (left + right) / 2
            let halfWidth = (right - left) / 2
            let across = (x - center) / max(halfWidth, 1)
            let distance = abs(across)
            let start: Float = 0.84
            let limit: Float = 0.97
            // Ease the farthest vertices around the edge so an oversized face
            // follows the body without flattening into a line at the silhouette.
            let projected = distance <= start ? distance
                : start + (limit - start) * (1 - exp(-(distance - start) / (limit - start)))
            let fittedX = center + (across < 0 ? -projected : projected) * halfWidth
            let depth = interpolate(rowDepth(first, at: fittedX), rowDepth(second, at: fittedX), weight)
            return (fittedX, depth)
        }

        private func rowDepth(_ row: [Float], at x: Float) -> Float {
            let across = min(max((x - row[0]) / max(row[1] - row[0], 1), 0), 1)
            let column = across * Float(columns - 1)
            let lower = Int(column)
            let upper = min(lower + 1, columns - 1)
            return interpolate(row[lower + 2], row[upper + 2], column - Float(lower))
        }

        private func interpolate(_ from: Float, _ to: Float, _ weight: Float) -> Float {
            from + (to - from) * weight
        }
    }
}
