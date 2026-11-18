//
//  OiSeedGarmentPhotoMaterial.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/18/26.
//

import CoreGraphics
import RealityKit
import UIKit

/// Composites prints into the fitted garment's original UVs without adding another mesh.
@MainActor enum OiSeedGarmentPhotoMaterial {
    static func resource(for top: OiWardrobeLook.Top) -> String {
        "photo-seed-\(top.rawValue)-top"
    }

    static func atlas(for look: OiWardrobeLook) throws -> CGImage {
        guard look.costume == nil, look.artwork.isValid else { throw OiPhotoDataError.unreadable }
        let layout = try OiPhotoPrintLayout.load(for: .top, in: look)
        let design = look.artwork.designs[OiPhotoSlot.top.itemID(in: look)] ?? OiPhotoDesign()
        let draft = try OiPhotoRenderer.load(design, sources: look.artwork.sources, layout: layout)
        guard let image = OiPhotoRenderer.atlas(layers: draft.layers, assets: draft.assets, panelSize: 1024,
            color: 0xFFFFFF, transparent: true, layout: layout).cgImage else {
            throw OiPhotoDataError.unreadable
        }
        return image
    }

    static func prepare(_ image: CGImage, top: OiWardrobeLook.Top,
                        color: UInt32 = 0xFFFFFF) async throws -> [OiCostumePhotoMaterial.Prepared] {
        try await OiCostumePhotoMaterial.prepare(image, resource: resource(for: top),
            baseTint: top == .postech ? 0xFFFFFF : color)
    }

    static func apply(_ prepared: [OiCostumePhotoMaterial.Prepared], to asset: Entity) throws {
        OiCostumePhotoMaterial.restore(asset)
        try OiCostumePhotoMaterial.apply(prepared, to: asset, resetBaseTint: true)
    }

    static func restore(_ asset: Entity) {
        OiCostumePhotoMaterial.restore(asset)
    }
}
