//
//  OiSeedTopPhotoTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 11/18/26.
//

import RealityKit
import UIKit
import XCTest
@testable import OiDonation

@MainActor
final class OiSeedTopPhotoTests: XCTestCase {
    func testFourTopsBakeSeparateSidesAndKeepPhotoColorsOnTintedFabric() async throws {
        let empty = canvas { _ in }
        let ink = canvas { context in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            context.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(x: 512, y: 0, width: 512, height: 512))
        }
        for top in OiWardrobeLook.Top.allCases {
            let resource = OiSeedGarmentPhotoMaterial.resource(for: top)
            let plain = try await OiCostumePhotoBaker.shared.bake(empty, resource: resource, baseTint: 0x55AA77)
            let printed = try await OiCostumePhotoBaker.shared.bake(ink, resource: resource, baseTint: 0x55AA77)
            XCTAssertEqual(plain.count, printed.count, top.rawValue)
            var front = 0, back = 0, unchanged = 0
            for (original, result) in zip(plain, printed) {
                let compressed = try Data(contentsOf: OiCostumePhotoBaker.resource(result.binding.map))
                let mapData = try (compressed as NSData).decompressed(using: .zlib) as Data
                let map = mapData.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
                let before = try rgba(original.image), after = try rgba(result.image)
                let pixels = result.binding.size * result.binding.size
                XCTAssertEqual(map.count, pixels * 2)
                for pixel in stride(from: 0, to: pixels, by: 67) {
                    let offset = pixel * 4, u = map[pixel * 2]
                    if u == 65535 {
                        XCTAssertEqual(Array(before[offset..<offset + 4]), Array(after[offset..<offset + 4]), top.rawValue)
                        unchanged += 1
                    } else if u < 32700 {
                        XCTAssertGreaterThan(after[offset], 245, top.rawValue)
                        XCTAssertLessThan(after[offset + 1], 8, top.rawValue)
                        XCTAssertLessThan(after[offset + 2], 8, top.rawValue)
                        front += 1
                    } else if u > 32835 {
                        XCTAssertGreaterThan(after[offset + 2], 245, top.rawValue)
                        XCTAssertLessThan(after[offset], 8, top.rawValue)
                        XCTAssertLessThan(after[offset + 1], 8, top.rawValue)
                        back += 1
                    }
                }
            }
            XCTAssertGreaterThan(front, 50, top.rawValue)
            XCTAssertGreaterThan(back, 50, top.rawValue)
            XCTAssertGreaterThan(unchanged, 1000, top.rawValue)
        }
    }

    func testFourTopsChangeOnlyFabricBaseColorAndRestoreOriginalMaterials() async throws {
        let ink = canvas { context in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            context.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(x: 512, y: 0, width: 512, height: 512))
        }
        for top in OiWardrobeLook.Top.allCases {
            let garment = OiSeedCucumberGarment(top: top)
            let asset = try await OiSeedCucumberModel.loadGarment(garment)
            let before = modelNodes(asset)
            let geometries = before.map(geometry)
            let materials = try before.map(material)
            let bounds = asset.visualBounds(relativeTo: asset)
            let targetName = top == .postech ? "PostechJacket" : try XCTUnwrap(garment.tintSurfaceName)
            let target = try XCTUnwrap(asset.findEntity(named: targetName))
            let prepared = try await OiSeedGarmentPhotoMaterial.prepare(ink, top: top, color: 0x55AA77)
            try OiSeedGarmentPhotoMaterial.apply(prepared, to: asset)
            let after = modelNodes(asset)
            XCTAssertEqual(after.count, before.count)
            XCTAssertEqual(asset.visualBounds(relativeTo: asset).extents, bounds.extents)
            XCTAssertEqual(asset.visualBounds(relativeTo: asset).center, bounds.center)
            for index in before.indices where after.indices.contains(index) {
                XCTAssertTrue(before[index] === after[index], top.rawValue)
                XCTAssertEqual(geometry(after[index]), geometries[index], before[index].name)
                let current = try material(after[index]), original = materials[index]
                assertOtherChannels(current, equalTo: original)
                if after[index] === target {
                    XCTAssertNotEqual(current.baseColor.texture?.resource, original.baseColor.texture?.resource)
                    assertWhite(current.baseColor.tint)
                } else {
                    XCTAssertEqual(current.baseColor.texture?.resource, original.baseColor.texture?.resource, before[index].name)
                    XCTAssertEqual(current.baseColor.tint, original.baseColor.tint, before[index].name)
                }
            }
            OiSeedGarmentPhotoMaterial.restore(asset)
            for (node, original) in zip(before, materials) {
                let restored = try material(node)
                XCTAssertEqual(restored.baseColor.texture?.resource, original.baseColor.texture?.resource, node.name)
                XCTAssertEqual(restored.baseColor.tint, original.baseColor.tint, node.name)
                assertOtherChannels(restored, equalTo: original)
            }
        }
    }

    func testSeedSnapshotRoundTripsLegacyAndInvalidatesPhotoIdentityWithoutSourceBytes() throws {
        var customization = try fixture(top: .hoodie)
        let first = try XCTUnwrap(customization.seedSnapshot)
        XCTAssertNotNil(first.topPhotoVersion)
        XCTAssertEqual(first.topColor, 0x55AA77)
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(first)
        XCTAssertEqual(try JSONDecoder().decode(OiSeedCucumberSnapshot.self, from: encoded), first)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["appearance", "garments", "topPhotoVersion", "topColor"])
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for source in try XCTUnwrap(customization.wardrobe).artwork.sources.keys { XCTAssertFalse(json.contains(source)) }
        XCTAssertFalse(json.contains("sources"))
        XCTAssertFalse(json.contains("layers"))

        object.removeValue(forKey: "topPhotoVersion")
        object.removeValue(forKey: "topColor")
        let legacy = try JSONDecoder().decode(OiSeedCucumberSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.topPhotoVersion)
        XCTAssertNil(legacy.topColor)
        XCTAssertEqual(legacy, .init(appearance: first.appearance, garments: first.garments))

        var look = try XCTUnwrap(customization.wardrobe)
        var design = try XCTUnwrap(look.artwork.designs["top-hoodie"])
        design.version = UUID().uuidString
        design.layers[0].placement.rotation += 12
        try look.artwork.set(design, for: "top-hoodie")
        customization.wardrobe = look
        let edited = try XCTUnwrap(customization.seedSnapshot)
        XCTAssertNotEqual(first, edited)
        XCTAssertNotEqual(first.portraitKey, edited.portraitKey)
        XCTAssertEqual(Set([first, edited]).count, 2)
        try look.artwork.set(nil, for: "top-hoodie")
        customization.wardrobe = look
        let removed = try XCTUnwrap(customization.seedSnapshot)
        XCTAssertNil(removed.topPhotoVersion)
        XCTAssertNil(removed.topColor)
    }

    func testLocalAndPublishedPhotosUseTheSameAtlasAndBothLoadOnSeedModel() async throws {
        let customization = try fixture(top: .hoodie)
        let look = customization.seedPhotoLook
        let snapshot = try XCTUnwrap(customization.seedSnapshot)
        let atlas = try OiSeedGarmentPhotoMaterial.atlas(for: look)
        let publication = try OiCucumberPublication(look: look, portrait: portrait(), seed: snapshot)
        XCTAssertEqual(Set(publication.images.keys), [.portrait, .top])
        XCTAssertTrue(publication.appearance.topTexture)
        XCTAssertFalse(publication.appearance.bottomTexture)
        let published = try OiPublishedCucumberImage.decode(XCTUnwrap(publication.images[.top]), part: .top)
        XCTAssertEqual(published.width, 2048)
        XCTAssertEqual(published.height, 1024)
        XCTAssertEqual(try rgba(atlas), try rgba(published))

        let localModel = try await OiSeedCucumberModel.make(snapshot: snapshot, look: look)
        let publicModel = try await OiSeedCucumberModel.make(snapshot: snapshot, publishedTopTexture: published)
        for model in [localModel, publicModel] {
            let hoodie = try XCTUnwrap(model.findEntity(named: OiSeedCucumberGarment.hoodie.rawValue))
            let cloth = try XCTUnwrap(hoodie.findEntity(named: "Hoodie"))
            XCTAssertNotNil(try material(cloth).baseColor.texture)
            assertWhite(try material(cloth).baseColor.tint)
            XCTAssertNotNil(model.findEntity(named: "LeftEye"))
            XCTAssertNotNil(model.findEntity(named: "Mouth"))
        }
        XCTAssertEqual(localModel.visualBounds(relativeTo: localModel).extents,
                       publicModel.visualBounds(relativeTo: publicModel).extents)
        let publicJSON = try JSONSerialization.data(withJSONObject: publication.appearance.payload)
        let publicText = try XCTUnwrap(String(data: publicJSON, encoding: .utf8))
        XCTAssertFalse(publicText.contains("sources"))
        XCTAssertFalse(publicText.contains("layers"))
    }

    func testBareAndUnselectedTopNeverExportStoredPhotos() throws {
        var customization = try fixture(top: .hoodie)
        customization.selectedSeedTop = nil
        let bare = try XCTUnwrap(customization.seedSnapshot)
        XCTAssertNil(bare.topPhotoVersion)
        let barePublication = try OiCucumberPublication(look: customization.seedPhotoLook, portrait: portrait(), seed: bare)
        XCTAssertEqual(Set(barePublication.images.keys), [.portrait])
        XCTAssertFalse(barePublication.appearance.topTexture)
        customization.selectedSeedTop = .cardigan
        let changed = try XCTUnwrap(customization.seedSnapshot)
        XCTAssertNil(changed.topPhotoVersion)
        let changedPublication = try OiCucumberPublication(look: customization.seedPhotoLook, portrait: portrait(), seed: changed)
        XCTAssertEqual(Set(changedPublication.images.keys), [.portrait])
        XCTAssertNotNil(customization.wardrobe?.artwork.designs["top-hoodie"], "Changing outfits must retain the editable design")
    }

    func testSeedPhotoRequiresMatchingDesignOrPublishedAtlas() async throws {
        let customization = try fixture(top: .hoodie)
        let snapshot = try XCTUnwrap(customization.seedSnapshot)
        var missing = customization.seedPhotoLook
        missing.artwork = .init()
        XCTAssertThrowsError(try OiCucumberPublication(look: missing, portrait: portrait(), seed: snapshot))
        do {
            _ = try await OiSeedCucumberModel.make(snapshot: snapshot, look: missing)
            XCTFail("A missing saved print must fail rather than silently publishing a bare shirt")
        } catch { XCTAssertTrue(error is OiPhotoDataError) }
        var wrong = customization.seedPhotoLook
        wrong.top = .tshirt
        XCTAssertThrowsError(try OiCucumberPublication(look: wrong, portrait: portrait(), seed: snapshot))
    }

    func testDraftRestorationAndPortraitCacheKeepCurrentSeedPhotoLook() throws {
        let original = try fixture(top: .hoodie)
        var restored = try JSONDecoder().decode(OiDraftCustomization.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        let source = OiStoryListPortraitSource.local(customization: restored, asset: "OiCats")
        guard case let .seedWithPhotos(seed, look) = source else { return XCTFail("Local photos need their saved look when captured") }
        XCTAssertEqual(seed, restored.seedSnapshot)
        XCTAssertEqual(look, restored.seedPhotoLook)
        let capture = OiStoryListPortraits.Capture(source: source)
        XCTAssertEqual(capture.look, look)
        XCTAssertEqual(capture.seed, seed)
        let cache = OiStoryListPortraitCache(observePressure: false)
        let owner = UUID()
        let image = UIImage(cgImage: canvas { _ in })
        cache.store(image, source: source, owner: owner)
        XCTAssertNotNil(cache.image(for: source, owner: owner))
        var updatedLook = try XCTUnwrap(restored.wardrobe)
        var design = try XCTUnwrap(updatedLook.artwork.designs["top-hoodie"])
        design.version = UUID().uuidString
        try updatedLook.artwork.set(design, for: "top-hoodie")
        restored.wardrobe = updatedLook
        let next = OiStoryListPortraitSource.local(customization: restored, asset: "OiCats")
        XCTAssertNotEqual(next, source)
        XCTAssertNil(cache.image(for: next, owner: owner))
        XCTAssertEqual(OiStoryListPortraitSource.local(customization: nil, asset: "OiCats", serverPath: "approved-portrait.png", serverSeed: seed),
                       .remote("approved-portrait.png"), "Remote photos must use the approved pixels instead of local editable sources")
    }

    func testPrivatePlacementRetainsSeedPhotosAndPreparesTheSeedModel() async throws {
        let customization = try fixture(top: .hoodie)
        var record = OiLocalDraft(draft: OiStoryDraft(), customization: customization)
        record.personalPlacement = .init(regionID: "pond", name: "Synthetic photo cucumber",
            latitude: 36.0126, longitude: 129.323, heightMeters: 1.8, headingDegrees: 45)
        let item = try XCTUnwrap(CampusAuthoredPlacement(personal: record, story: nil))
        XCTAssertEqual(item.seed, customization.seedSnapshot)
        XCTAssertEqual(item.wardrobe, customization.seedPhotoLook)
        XCTAssertNil(item.submittedArtwork)
        let scene = CampusExploreScene()
        await scene.preparePlacements(wardrobe: item.wardrobe, seed: item.seed)
        XCTAssertTrue(scene.placementReady)
        XCTAssertNil(scene.placementError)

        var legacy = OiDraftCustomization()
        legacy.wardrobe = OiWardrobeLook()
        record.customization = legacy
        let oldItem = try XCTUnwrap(CampusAuthoredPlacement(personal: record, story: nil))
        XCTAssertNil(oldItem.seed)
        XCTAssertEqual(oldItem.wardrobe, legacy.wardrobe)
    }

    private func fixture(top: OiWardrobeLook.Top) throws -> OiDraftCustomization {
        func photo(_ color: UIColor, marker: CGRect) throws -> OiPhotoImageAsset {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48), format: format).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
                UIColor.white.setFill(); context.fill(marker)
            }
            return try OiPhotoRenderer.asset(image)
        }
        let front = try photo(.red, marker: CGRect(x: 0, y: 0, width: 9, height: 15))
        let back = try photo(.blue, marker: CGRect(x: 43, y: 29, width: 18, height: 9))
        let layers = [
            OiPhotoLayer(source: front.id, side: .front, placement: .init(x: 0.43, y: 0.47, width: 0.65, rotation: 17)),
            OiPhotoLayer(source: back.id, side: .back, placement: .init(x: 0.61, y: 0.56, width: 0.55, rotation: -12))
        ]
        var look = OiWardrobeLook(); look.top = top
        try look.artwork.set(OiPhotoDesign(layers: layers), sources: [front.id: front.data, back.id: back.data], for: "top-" + top.rawValue)
        var customization = OiDraftCustomization()
        customization.seedAppearance = .init()
        customization.selectedSeedTop = top
        customization.garmentColors["상의"] = 0x55AA77
        customization.wardrobe = look
        return customization
    }

    private func canvas(_ draw: (CGContext) -> Void) -> CGImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format).image { draw($0.cgContext) }.cgImage!
    }

    private func portrait() throws -> Data {
        try XCTUnwrap(UIImage(cgImage: canvas { context in
            context.setFillColor(UIColor.green.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
        }).pngData())
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    private func modelNodes(_ root: Entity) -> [Entity] {
        (root.components[ModelComponent.self] == nil ? [] : [root]) + root.children.flatMap(modelNodes)
    }

    private func material(_ node: Entity) throws -> PhysicallyBasedMaterial {
        try XCTUnwrap(node.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial, node.name)
    }

    private struct Geometry: Equatable {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var indices: [UInt32] = []
    }

    private func geometry(_ node: Entity) -> Geometry {
        var value = Geometry()
        guard let mesh = node.components[ModelComponent.self]?.mesh else { return value }
        for model in mesh.contents.models {
            for part in model.parts {
                value.positions += part.positions.elements
                value.normals += part.normals?.elements ?? []
                value.coordinates += part.textureCoordinates?.elements ?? []
                value.indices += part.triangleIndices?.elements ?? []
            }
        }
        return value
    }

    private func assertOtherChannels(_ current: PhysicallyBasedMaterial, equalTo original: PhysicallyBasedMaterial) {
        XCTAssertEqual(current.normal.texture?.resource, original.normal.texture?.resource)
        XCTAssertEqual(current.roughness.scale, original.roughness.scale)
        XCTAssertEqual(current.roughness.texture?.resource, original.roughness.texture?.resource)
        XCTAssertEqual(current.metallic.scale, original.metallic.scale)
        XCTAssertEqual(current.metallic.texture?.resource, original.metallic.texture?.resource)
    }

    private func assertWhite(_ color: UIColor) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        for component in [red, green, blue, alpha] { XCTAssertEqual(component, 1, accuracy: 0.0001) }
    }
}
