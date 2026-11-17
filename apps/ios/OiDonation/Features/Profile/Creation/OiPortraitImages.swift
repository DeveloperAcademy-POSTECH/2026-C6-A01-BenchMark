//
//  OiPortraitImages.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/16/26.
//

import UIKit

/// One CPU worker and one decoded portrait, shared across the two customization steps.
/// PNG bytes, resolution and alpha are preserved; no image is downsampled.
actor OiPortraitImages {
    static let shared = OiPortraitImages()
    private var entry: (key: String, data: Data, image: UIImage)?

    func clear() { entry = nil }

    func cached(key: String) -> UIImage? { entry?.key == key ? entry?.image : nil }

    /// The PNG rendered for `key` while STEP 3 was still open, so STEP 4 can use it without rendering again (#386).
    func cachedData(key: String) -> Data? { entry?.key == key ? entry?.data : nil }

    func restore(_ data: Data, key: String) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let entry, entry.key == key, entry.data == data { return entry.image }
        return autoreleasepool {
            guard let image = UIImage(data: data), OiPortraitMatte.hasTransparentBackground(image),
                  !Task.isCancelled else { return nil }
            let prepared = image.preparingForDisplay() ?? image
            entry = (key, data, prepared)
            return prepared
        }
    }

    func encode(_ image: UIImage, key: String) -> Data? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            guard OiPortraitMatte.hasTransparentBackground(image), let data = image.pngData(),
                  !Task.isCancelled else { return nil }
            entry = (key, data, image)
            return data
        }
    }

    func thumbnail(_ url: URL) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            return image.preparingForDisplay() ?? image
        }
    }

    func matte(black: UIImage, white: UIImage) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool { OiPortraitMatte.image(black: black, white: white) }
    }
}
