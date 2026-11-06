import RealityKit
import UIKit

/// Same authored geometry and material composition for closet, campus and AR.
@MainActor enum OiWardrobeAsset {
    static func prepare(_ look: OiWardrobeLook, existing: Entity? = nil,
                        editingSlot: OiPhotoSlot? = nil, previewTexture: TextureResource? = nil, previewImage: CGImage? = nil) async throws -> (Entity, [OiPhotoSlot: Entity]) {
        guard look.artwork.isValid else { throw OiPhotoDataError.unreadable }
        let root: Entity
        if let existing { root = existing.clone(recursive: true)
            OiCostumePhotoMaterial.restore(root)
            for child in Array(root.children) where child.name == "OiPhotoOverlay" { child.removeFromParent() }
        }
        else { root = try await Entity(contentsOf: url(look.modelName, folder: "Wardrobe")) }
        var overlays: [OiPhotoSlot: Entity] = [:]
        for slot in OiPhotoSlot.allCases where slot.supports(look) {
            let design = look.artwork.designs[slot.itemID(in: look)]
            guard design != nil || slot.fabric(in: look) != nil || editingSlot == slot else { continue }
            let layout = try OiPhotoPrintLayout.load(resource: slot.resource(in: look))
            if slot.preservesOriginalMaterial(in: look) {
                let image: CGImage
                if editingSlot == slot, let previewImage { image = previewImage }
                else {
                    let draft = try OiPhotoRenderer.load(design ?? OiPhotoDesign(), sources: look.artwork.sources)
                    guard let cg = OiPhotoRenderer.atlas(layers: draft.layers, assets: draft.assets, panelSize: 1024,
                        color: 0xFFFFFF, transparent: true, layout: layout).cgImage else { throw OiPhotoDataError.unreadable }
                    image = cg
                }
                let prepared = try await OiCostumePhotoMaterial.prepare(image, resource: slot.resource(in: look))
                try Task.checkCancellation()
                try OiCostumePhotoMaterial.apply(prepared, to: root)
                continue
            }
            let garment = try await Entity(contentsOf: url(slot.resource(in: look), folder: "WardrobePhotoUV"))
            let texture: TextureResource
            if editingSlot == slot, let previewTexture { texture = previewTexture }
            else {
                let draft = try OiPhotoRenderer.load(design ?? OiPhotoDesign(), sources: look.artwork.sources)
                let image = OiPhotoRenderer.atlas(layers: draft.layers, assets: draft.assets, panelSize: 1024,
                    color: slot.color(in: look), fabric: slot.fabric(in: look), layout: layout)
                guard let cg = image.cgImage else { throw OiPhotoDataError.unreadable }
                texture = try await TextureResource(image: cg, options: .init(semantic: .color))
            }
            garment.name = "OiPhotoOverlay"
            applyPhoto(texture, to: garment); overlays[slot] = garment
            try Task.checkCancellation()
        }
        return (root, overlays)
    }

    static func assemble(_ look: OiWardrobeLook, root: Entity, overlays: [OiPhotoSlot: Entity]) {
        if look.costume == nil { applyColors(look, to: root) }
        for slot in OiPhotoSlot.allCases { setRole(slot.role, visible: overlays[slot] == nil, in: root) }
        for node in overlays.values { root.addChild(node) }
    }

    /// Fixed 150cm height, feet at zero, facing +Z. Never edits the source mesh.
    static func loadForPlacement(_ look: OiWardrobeLook) async throws -> Entity {
        let (model, overlays) = try await prepare(look)
        try Task.checkCancellation()
        assemble(look, root: model, overlays: overlays)
        let bounds = model.visualBounds(relativeTo: nil)
        guard bounds.extents.y.isFinite, bounds.extents.y > 0.001 else { throw OiPhotoDataError.unreadable }
        let offset = Entity(); offset.addChild(model)
        offset.position = -SIMD3(bounds.center.x, bounds.min.y, bounds.center.z)
        let sized = Entity(); sized.addChild(offset)
        sized.scale = SIMD3(repeating: 1.5 / bounds.extents.y)
        let result = Entity(); result.addChild(sized)
        return result
    }
    static func url(_ name: String, folder: String) throws -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: folder)
                ?? Bundle.main.url(forResource: name, withExtension: "usdz") else { throw CocoaError(.fileNoSuchFile) }
        return url
    }
    static func setRole(_ role: String, visible: Bool, in node: Entity) {
        if node.name == role { node.isEnabled = visible; return }
        for child in node.children { setRole(role, visible: visible, in: child) }
    }
    static func applyPhoto(_ texture: TextureResource, to node: Entity) {
        if var component = node.components[ModelComponent.self] {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .white, texture: .init(texture))
            material.roughness = .init(floatLiteral: 0.9)
            material.metallic = .init(floatLiteral: 0)
            material.faceCulling = .none
            component.materials = component.materials.map { _ in material }
            node.components.set(component)
        }
        for child in node.children { applyPhoto(texture, to: child) }
    }
    static func applyColors(_ look: OiWardrobeLook, to root: Entity) {
        func visit(_ node: Entity, part: String?) {
            let role = ["Top", "Bottom", "Shoes"].first(where: { node.name == $0 || node.name.hasPrefix($0 + "_") || node.name.hasPrefix($0 + ".") }) ?? part
            if var component = node.components[ModelComponent.self] {
                component.materials = component.materials.map { original in
                    guard var material = original as? PhysicallyBasedMaterial else { return original }
                    material.faceCulling = .none
                    material.metallic = .init(floatLiteral: 0)
                    if let role {
                        let rgb = role == "Bottom" ? look.bottomColor : role == "Shoes" ? look.shoeColor : look.top == .postech ? 0xFFFFFF : look.topColor
                        material.baseColor.tint = UIColor(wardrobeRGB: rgb)
                        material.roughness = .init(floatLiteral: role == "Top" && look.top == .postech ? 0.75 : 0.88)
                    }
                    return material
                }
                node.components.set(component)
            }
            for child in node.children { visit(child, part: role) }
        }
        visit(root, part: nil)
    }
}
