import SwiftUI
import UIKit

struct ARCharacterThumbnail: View {
    let character: ARCharacter
    var size: CGFloat = 52
    private static let previewCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 5
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
    private var wardrobeImage: UIImage? {
        guard character.wardrobeCostumeID != nil else { return nil }
        let key = character.rawValue as NSString
        if let image = Self.previewCache.object(forKey: key) { return image }
        guard
              let url = Bundle.main.url(forResource: character.previewImageName, withExtension: "png", subdirectory: "ARThumbnails")
                ?? Bundle.main.url(forResource: character.previewImageName, withExtension: "png") else { return nil }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        Self.previewCache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }

    var body: some View {
        Group {
            if let wardrobeImage { Image(uiImage: wardrobeImage).resizable().scaledToFit() }
            else { Image(character.previewImageName).resizable().scaledToFit() }
        }
            .padding(4)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A single 2D image; never allocate a second 3D renderer for the selection button.
struct ARSelectedCharacterThumbnail: View {
    let character: ARCharacter
    let subject: ARCameraSubject?
    var size: CGFloat = 40
    @State private var portrait: UIImage?

    var body: some View {
        Group {
            if subject == nil { ARCharacterThumbnail(character: character, size: size) }
            else if let portrait { Image(uiImage: portrait).resizable().scaledToFit().padding(4) }
            else { Image(systemName: "leaf.fill").font(.title3).foregroundStyle(.mint) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: subject?.id) {
            portrait = nil
            guard let load = subject?.loadThumbnail else { return }
            let image = try? await load()
            guard !Task.isCancelled else { return }
            portrait = image
        }
    }
}
