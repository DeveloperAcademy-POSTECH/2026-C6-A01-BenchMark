//
//  OiCucumberPublication.swift
//  OiDonation
//
//  Created by Jang Jihoon on 11/8/26.
//

import CryptoKit
import ImageIO
import RealityKit
import UIKit

/// The 3D renderer and publication use the same garment atlases. Only pixels inside the
/// print frames leave the device; unused outfits and source photos stay local.
struct OiCucumberPublication {
    typealias Part = OiCucumberArtworkReference.Part
    let appearance: OiCucumberAppearance
    let images: [Part: Data]

    @MainActor init(look: OiWardrobeLook, portrait: Data) throws {
        guard look.artwork.isValid else { throw OiPhotoDataError.unreadable }
        _ = try OiPublishedCucumberImage.decode(portrait, part: .portrait)
        var images: [Part: Data] = [.portrait: portrait]
        for slot in OiPhotoSlot.allCases where slot.supports(look) {
            guard look.artwork.designs[slot.itemID(in: look)] != nil || slot.fabric(in: look) != nil else { continue }
            let part: Part = slot == .top ? .top : .bottom
            let atlas = try OiWardrobeAsset.atlas(for: slot, in: look)
            guard let bytes = UIImage(cgImage: atlas).pngData() else { throw OiPhotoDataError.unreadable }
            _ = try OiPublishedCucumberImage.decode(bytes, part: part)
            images[part] = bytes
        }
        func appearance(id: UUID) -> OiCucumberAppearance {
            .init(id: id, top: look.top.rawValue, bottom: look.bottom.rawValue, costume: look.costume?.rawValue,
                  topColor: look.topColor, bottomColor: look.bottomColor, shoeColor: look.shoeColor,
                  topTexture: images[.top] != nil, bottomTexture: images[.bottom] != nil)
        }
        // A failed upload can be retried with the same paths. A changed look always gets new paths.
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        var hash = SHA256()
        let emptyID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        hash.update(data: try encoder.encode(appearance(id: emptyID)))
        for part in Part.allCases {
            if let image = images[part] { hash.update(data: Data(SHA256.hash(data: image))) }
        }
        let b = Array(hash.finalize().prefix(16))
        let id = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                             b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        self.appearance = appearance(id: id)
        self.images = images
    }
}

struct OiStoryCardPublication {
    let id: UUID
    let png: Data
    let parts: [StoryCard.Part: Data]
    var format: Int { parts.isEmpty ? 1 : 2 }

    init(png: Data) throws {
        _ = try OiPublishedCucumberImage.decode(png, part: .portrait)
        let b = Array(SHA256.hash(data: png).prefix(16))
        id = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                         b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        self.png = png
        parts = [:]
    }

    init(front: Data, back: Data, frontPreview: Data, backPreview: Data) throws {
        let values: [StoryCard.Part: Data] = [.front: front, .back: back, .frontPreview: frontPreview, .backPreview: backPreview]
        var hash = SHA256()
        hash.update(data: Data("oi-card-duplex-v2".utf8))
        for part in StoryCard.Part.allCases {
            _ = try OiPublishedCucumberImage.decode(values[part]!, part: .portrait)
            hash.update(data: Data(SHA256.hash(data: values[part]!)))
        }
        let bytes = Array(hash.finalize().prefix(16))
        id = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
                         bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        png = front
        parts = values
    }
}

enum OiPublishedCucumberImage {
    static let bucket = "oi-story-media"

    static func decode(_ data: Data, part: OiCucumberArtworkReference.Part) throws -> CGImage {
        guard data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.png",
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              part == .portrait ? (1...2048).contains(width) && (1...2048).contains(height) : (width == 2048 && height == 1024),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw OiPhotoDataError.unreadable }
        return image
    }
}

extension OiRemoteStore {
    /// The public AR never reads wardrobe data from the current device's draft vault.
    func cucumberModel(_ reference: OiCucumberArtworkReference) async throws -> Entity {
        let appearance = reference.appearance
        guard let top = OiWardrobeLook.Top(rawValue: appearance.top),
              let bottom = OiWardrobeLook.Bottom(rawValue: appearance.bottom) else { throw OiServiceError.invalidInput }
        var look = OiWardrobeLook()
        look.top = top; look.bottom = bottom
        if let costume = appearance.costume {
            guard let value = OiWardrobeLook.Costume(rawValue: costume) else { throw OiServiceError.invalidInput }
            look.costume = value
        }
        look.topColor = appearance.topColor; look.bottomColor = appearance.bottomColor; look.shoeColor = appearance.shoeColor
        var textures: [OiPhotoSlot: CGImage] = [:]
        for part in reference.parts where part != .portrait {
            let image = try await cucumberImage(reference.path(part), part: part)
            guard let cgImage = image.cgImage else { throw OiPhotoDataError.unreadable }
            textures[part == .top ? .top : .bottom] = cgImage
        }
        try Task.checkCancellation()
        return try await OiWardrobeAsset.loadForPlacement(look, textures: textures)
    }
}
