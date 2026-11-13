//
//  CampusMapAppearance.swift
//  OiDonation
//
//  Created by Codex on 11/11/26.
//

import RealityKit
import UIKit

enum CampusMapAppearance {
    case original
    case apricotCream

    var background: UIColor {
        self == .original
            ? UIColor(red: 0.78, green: 0.86, blue: 0.70, alpha: 1)
            : Self.color(0xFFF8E9)
    }

    // Screen-space backdrop, independent of scene exposure and camera rotation.
    var backdropColors: [UIColor] {
        self == .original
            ? [background, background, background]
            : [Self.color(0xFFF6E5), Self.color(0xFAF6E2), Self.color(0xE4EDC8)]
    }

    // A fixed daylight rig is used only by the non-AR campus renderer. The
    // visible backdrop is deliberately independent from the light environment.
    @MainActor @discardableResult
    func configureLighting(in view: RealityKit.ARView, root: Entity) throws -> DirectionalLight {
        let sky = self == .apricotCream ? try Self.daylight.get() : nil
        root.findEntity(named: "campus-lighting")?.removeFromParent()
        let rig = Entity()
        rig.name = "campus-lighting"
        let sun = DirectionalLight()
        sun.name = "campus-sun"
        sun.light.intensity = self == .apricotCream ? 1800 : 2200
        sun.light.color = self == .apricotCream ? Self.color(0xFFFAF1) : .white
        sun.look(at: .zero, from: SIMD3(-35, 75, 40), relativeTo: nil)
        if self == .original {
            sun.look(at: .zero, from: SIMD3(30, 60, 40), relativeTo: nil)
        } else {
            sun.shadow = .init(shadowProjection: .automatic(maximumDistance: 650), depthBias: 1)
        }
        rig.addChild(sun)
        let fill = DirectionalLight()
        fill.name = "campus-fill"
        fill.light.intensity = self == .apricotCream ? 650 : 900
        fill.look(at: .zero, from: SIMD3(-30, 40, -50), relativeTo: nil)
        rig.addChild(fill)
        view.environment.lighting.resource = sky
        view.environment.lighting.intensityExponent = self == .apricotCream ? 1 : 0
        root.addChild(rig)
        return sun
    }

    // A tiny neutral hemisphere avoids a bundled/default environment tinting
    // the palette. The lower hemisphere is dimmer to retain form and contact.
    @MainActor private static let daylight: Result<EnvironmentResource, Error> = Result {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 64), format: format).image { context in
            let colors = [UIColor(white: 0.85, alpha: 1).cgColor,
                          UIColor(white: 0.7, alpha: 1).cgColor,
                          UIColor(white: 0.45, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
        }
        return try EnvironmentResource(equirectangular: image.cgImage!, withName: "campus-neutral-daylight")
    }

    // The palette is generated from the same 507 tiles as campus-mobile.oimesh.
    // MeshResources remain shared; only this clone's material components change.
    @MainActor func makeMap(from original: Entity) throws -> Entity {
        let copy = original.clone(recursive: true)
        guard self == .apricotCream else { return copy }
        let colors = try Self.apricotColors.get()
        guard copy.children.count <= colors.count else { throw CampusMeshLoader.Failure.invalidAsset }
        for child in copy.children {
            guard let model = child as? ModelEntity,
                  let index = Int(child.name.replacingOccurrences(of: "campus-tile-", with: "")),
                  colors.indices.contains(index) else { throw CampusMeshLoader.Failure.invalidAsset }
            model.model?.materials = [SimpleMaterial(color: Self.color(colors[index]), roughness: 0.75, isMetallic: false)]
        }
        copy.name = "POSTECH v09 apricot cream copy"
        return copy
    }

    private static let apricotColors: Result<[UInt32], Error> = Result {
        guard let url = Bundle.main.url(forResource: "campus-apricot-cream", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([UInt32].self, from: Data(contentsOf: url))
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
