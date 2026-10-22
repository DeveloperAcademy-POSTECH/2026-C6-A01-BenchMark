// Created by 이돈혁

import ImageIO
import PhotosUI
import SwiftUI
import UIKit

enum CollageImageError: LocalizedError {
    case unreadable, incomplete, exportFailed
    var errorDescription: String? {
        switch self {
        case .unreadable: "사진을 불러오지 못했어요. iCloud 연결을 확인하거나 다른 사진을 선택해 주세요."
        case .incomplete: "모든 칸에 사진을 넣어 주세요."
        case .exportFailed: "이미지를 만들지 못했어요. 다시 시도해 주세요."
        }
    }
}

actor CollageImageLoader {
    func load(_ item: PhotosPickerItem) async throws -> UIImage {
        guard let data = try await item.loadTransferable(type: Data.self) else { throw CollageImageError.unreadable }
        try Task.checkCancellation()
        return try decode(data)
    }

    func decode(_ data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CollageImageError.unreadable }
        return UIImage(cgImage: image)
    }
}

struct CollagePhoto {
    var image: UIImage?
    var crop = CollageCrop()
}

enum CollageRenderer {
    static func render(photos: [CollagePhoto], arrangement: CollageArrangement, cropped: Bool) throws -> UIImage {
        guard !photos.isEmpty, photos.count == arrangement.frames.count,
              photos.allSatisfy({ $0.image != nil }), arrangement.aspectRatio.isFinite, arrangement.aspectRatio > 0 else {
            throw CollageImageError.incomplete
        }
        let ratio = arrangement.aspectRatio
        let size = CGSize(width: ratio >= 1 ? 2048 : max(1, (2048 * ratio).rounded()),
                          height: ratio >= 1 ? max(1, (2048 / ratio).rounded()) : 2048)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (photo, normalized) in zip(photos, arrangement.frames) {
                guard let image = photo.image else { continue }
                let cell = CGRect(x: normalized.minX * size.width, y: normalized.minY * size.height,
                                  width: normalized.width * size.width, height: normalized.height * size.height)
                context.cgContext.saveGState()
                context.cgContext.clip(to: cell)
                if cropped {
                    let frame = photo.crop.imageFrame(imageSize: image.size, cellSize: cell.size)
                    image.draw(in: frame.offsetBy(dx: cell.minX, dy: cell.minY))
                } else {
                    image.draw(in: cell)
                }
                context.cgContext.restoreGState()
            }
        }
    }
}
