#if DEBUG
import RealityKit
import Foundation

/// Opt-in bundle/geometry integration checks. No server or saved-placement writes.
@MainActor enum OiWardrobeFieldChecks {
    static let previewLook = try? look()
    static func look() throws -> OiWardrobeLook {
        var look = OiWardrobeLook()
        look.top = .hoodie; look.topColor = 0xBFDCD2
        look.fabrics["bottom-long"] = .classicBlue
        let photo = try OiPhotoRenderer.asset(OiPhotoRenderer.sample())
        try look.artwork.set(OiPhotoDesign(layers: [
            OiPhotoLayer(source: photo.id, placement: .init(x: 0.5, y: 0.55, width: 0.35, rotation: 12)),
            OiPhotoLayer(source: photo.id, side: .back)
        ]), sources: [photo.id: photo.data], for: "top-hoodie")
        return look
    }
    static func verifyAssets() async {
        do {
            var looks = [try look()]
            for costume in OiWardrobeLook.Costume.allCases {
                var look = OiWardrobeLook(); look.costume = costume; looks.append(look)
            }
            for look in looks {
                let entity = try await OiWardrobeAsset.loadForPlacement(look)
                for angle in [0.0, 90, 180, 270] {
                    entity.orientation = CampusOiAsset.heading(angle)
                    let bounds = entity.visualBounds(relativeTo: nil)
                    guard abs(bounds.extents.y - 1.5) < 0.001, abs(bounds.min.y) < 0.001 else {
                        throw OiPhotoDataError.unreadable
                    }
                }
                print("[WardrobeFieldCheck] \(look.modelName) height-and-ground PASS")
            }
            print("[WardrobeFieldCheck] ASSETS PASS")
        } catch { print("[WardrobeFieldCheck] ASSETS FAIL \(error)") }
    }
}
#endif
