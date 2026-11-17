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

enum OiSeedCucumberGarment: Hashable, CaseIterable {
    case whiteTshirt, hoodie, cardigan, postechJacket, longPants, shorts, sneakers
    case costume(OiWardrobeLook.Costume)
    case costumeProposal(OiWardrobeLook.Costume, OiSeedCostumeProposal)

    static var allCases: [Self] {
        [.whiteTshirt, .hoodie, .cardigan, .postechJacket, .longPants, .shorts, .sneakers]
            + OiWardrobeLook.Costume.allCases.map(Self.costume)
    }

    var rawValue: String {
        switch self {
        case .whiteTshirt: "SeedCucumberWhiteTshirt"
        case .hoodie: "SeedCucumberHoodie"
        case .cardigan: "SeedCucumberCardigan"
        case .postechJacket: "SeedCucumberPostechJacket"
        case .longPants: "SeedCucumberLongPants"
        case .shorts: "SeedCucumberShorts"
        case .sneakers: "SeedCucumberSneakers"
        case .costume(let costume): "seed-costume-" + costume.rawValue
        case .costumeProposal(let costume, let proposal):
            "seed-costume-\(costume.rawValue)-proposal-\(proposal.rawValue)"
        }
    }

    enum Slot: CaseIterable {
        case top, bottom, shoes, costume
    }

    init(top: OiWardrobeLook.Top) {
        self = switch top {
        case .tshirt: .whiteTshirt
        case .hoodie: .hoodie
        case .cardigan: .cardigan
        case .postech: .postechJacket
        }
    }

    init(bottom: OiWardrobeLook.Bottom) {
        self = switch bottom {
        case .long: .longPants
        case .shorts: .shorts
        }
    }

    var slot: Slot {
        switch self {
        case .whiteTshirt, .hoodie, .cardigan, .postechJacket: .top
        case .longPants, .shorts: .bottom
        case .sneakers: .shoes
        case .costume, .costumeProposal: .costume
        }
    }

    var title: String {
        switch self {
        case .whiteTshirt: OiWardrobeLook.Top.tshirt.title
        case .hoodie: OiWardrobeLook.Top.hoodie.title
        case .cardigan: OiWardrobeLook.Top.cardigan.title
        case .postechJacket: OiWardrobeLook.Top.postech.title
        case .longPants: OiWardrobeLook.Bottom.long.title
        case .shorts: OiWardrobeLook.Bottom.shorts.title
        case .sneakers: "흰 운동화"
        case .costume(let costume), .costumeProposal(let costume, _): costume.title
        }
    }

    var coveredSeedParts: Set<String> {
        switch self {
        case .costumeProposal:
            ["Body", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]
        case .costume(.dinosaur), .costume(.raincoat), .costume(.bee), .costume(.cat), .costume(.catBear),
             .costume(.astronaut), .costume(.astronautNavy), .costume(.scientist):
            ["Body", "LeftArm", "RightArm", "LeftLeg", "RightLeg"]
        case .hoodie, .postechJacket:
            ["Body", "LeftArm", "RightArm"]
        case .costume(.baseball), .costume(.postechSelfie):
            ["LeftArm", "RightArm", "LeftLeg", "RightLeg"]
        case .costume(.schoolUniform), .costume(.schoolUniformTrousers), .costume(.scientistGoggles), .sneakers:
            ["LeftLeg", "RightLeg"]
        default: []
        }
    }

    var rendersHoodInterior: Bool { self == .hoodie || hoodAttachments != nil }

    // Positions are in the unscaled seed model's authored coordinates.
    var hoodAttachments: (faceDepth: Float, stem: SIMD3<Float>)? {
        switch self {
        case .costumeProposal(let costume, _):
            Self.costume(costume).hoodAttachments.map { (0, $0.stem) }
        case .costume(.bee): (0, SIMD3(-0.028, -0.084, -0.010))
        case .costume(.cat): (0.034, SIMD3(-0.024, -0.061, 0.022))
        case .costume(.catBear): (0.023, SIMD3(-0.036, -0.064, -0.066))
        case .costume(.raincoat): (0.019, SIMD3(-0.018, -0.052, 0.012))
        case .costume(.dinosaur): (0.088, SIMD3(0.010, -0.018, 0.068))
        case .costume(.astronaut): (0.040, SIMD3(-0.008, -0.010, -0.050))
        case .costume(.astronautNavy): (0.062, SIMD3(0.008, -0.002, -0.058))
        default: nil
        }
    }
}

@MainActor enum OiSeedCucumberModel {
    private static let bodyTransformName = "SeedCucumberBodyTransform"
    private static let faceAttachmentName = "SeedCucumberFaceAttachment"
    private static let stemAttachmentName = "SeedCucumberStemAttachment"
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
        asset.name = "SeedCucumberMaster"

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

        try attachParts(faceParts.map { $0.0 }, named: faceAttachmentName, from: asset, to: sized)
        try attachParts(["Stem"], named: stemAttachmentName, from: asset, to: sized)
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
        if garment.rendersHoodInterior {
            configureHoodSurfaces(in: asset)
        }
        return asset
    }

    private static func configureHoodSurfaces(in entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            let isHead = entity.name == "VisibleBody" || entity.name == "VisibleBodyUpper"
            model.materials = model.materials.map { material in
                guard var surface = material as? PhysicallyBasedMaterial else { return material }
                if isHead { surface.blending = .opaque }
                // Keeping both sides renders the fabric when viewed through the opening.
                if case .opaque = surface.blending { surface.faceCulling = .none }
                return surface
            }
            entity.components.set(model)
        }
        for child in entity.children { configureHoodSurfaces(in: child) }
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

    static func updateCoverage(for garments: Set<OiSeedCucumberGarment>, on model: Entity) {
        guard let master = model.findEntity(named: "SeedCucumberMaster") else { return }
        let covered: Set<String> = garments.reduce(into: []) { parts, garment in
            parts.formUnion(garment.coveredSeedParts)
        }
        // Some garments include the original visible part with its covered section removed.
        // Hide the untrimmed part only while that garment is mounted.
        for part in ["Body", "LeftArm", "RightArm", "LeftLeg", "RightLeg"] {
            master.findEntity(named: part)?.isEnabled = !covered.contains(part)
        }
        let attachment = garments.compactMap(\.hoodAttachments).first
        model.findEntity(named: faceAttachmentName)?.position.z = attachment?.faceDepth ?? 0
        model.findEntity(named: stemAttachmentName)?.position = attachment?.stem ?? .zero
    }

    private static func attachParts(_ names: [String], named groupName: String, from asset: Entity, to parent: Entity) throws {
        let attachment = Entity()
        attachment.name = groupName
        parent.addChild(attachment)
        for name in names {
            guard let part = asset.findEntity(named: name) else { throw AssetError.missingPart(name) }
            attachment.addChild(part, preservingWorldTransform: true)
        }
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


extension OiDraftCustomization {
    var seedGarments: Set<OiSeedCucumberGarment> {
        switch selectedSeedSet {
        case .costume(let costume):
            if let proposal = selectedSeedProposal {
                return [.costumeProposal(costume, proposal)]
            }
            return [.costume(costume)]
        case .postech: return [.postechJacket, .longPants, .sneakers]
        case nil: break
        }
        var garments: Set<OiSeedCucumberGarment> = []
        if let top = selectedSeedTop { garments.insert(.init(top: top)) }
        if let bottom = selectedSeedBottom { garments.insert(.init(bottom: bottom)) }
        if seedSneakers == true { garments.insert(.sneakers) }
        return garments
    }

    var seedSnapshot: OiSeedCucumberSnapshot? {
        let garments = seedGarments
        guard seedAppearance != nil || !garments.isEmpty else { return nil }
        return OiSeedCucumberSnapshot(appearance: seedAppearance ?? .init(), garments: garments.map(\.rawValue).sorted())
    }

    var portraitLook: OiWardrobeLook? { seedSnapshot != nil ? OiWardrobeLook() : wardrobe }
}

extension OiSeedCucumberModel {
    static func make(snapshot: OiSeedCucumberSnapshot) async throws -> Entity {
        let supported = OiSeedCucumberGarment.allCases + OiWardrobeLook.Costume.allCases.flatMap { costume in
            OiSeedCostumeProposal.options(for: costume).map { OiSeedCucumberGarment.costumeProposal(costume, $0) }
        }
        let model = try await make(appearance: snapshot.appearance)
        var selected: Set<OiSeedCucumberGarment> = []
        for name in snapshot.garments {
            guard let garment = supported.first(where: { $0.rawValue == name }) else { throw AssetError.invalidMesh(name) }
            try await setGarment(garment, asset: loadGarment(garment), on: model)
            selected.insert(garment)
        }
        updateCoverage(for: selected, on: model)
        return model
    }
}
