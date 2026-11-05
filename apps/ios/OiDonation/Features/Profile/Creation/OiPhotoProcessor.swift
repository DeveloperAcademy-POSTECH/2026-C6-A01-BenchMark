import ImageIO
import UIKit

/// The real editor and isolated practice flow use the same photo processing.
enum OiPhotoProcessor {
    static func prepare(_ data: Data) throws -> Data {
        guard data.count <= 40_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else { throw OiServiceError.invalidInput }
        return jpeg
    }

    static func edit(_ data: Data, operation: OiPhotoEdit) throws -> Data {
        guard let image = UIImage(data: data), let cg = image.cgImage else { throw OiServiceError.invalidInput }
        let edited: UIImage
        switch operation {
        case .crop(let normalizedRect):
            guard [normalizedRect.origin.x, normalizedRect.origin.y, normalizedRect.width, normalizedRect.height].allSatisfy({ $0.isFinite }),
                  normalizedRect.width > 0, normalizedRect.height > 0,
                  normalizedRect.minX >= 0, normalizedRect.minY >= 0,
                  normalizedRect.maxX <= 1.000001, normalizedRect.maxY <= 1.000001 else { throw OiServiceError.invalidInput }
            let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
            let pixels = CGRect(x: normalizedRect.minX * bounds.width, y: normalizedRect.minY * bounds.height,
                                width: normalizedRect.width * bounds.width, height: normalizedRect.height * bounds.height)
                .integral.intersection(bounds)
            guard pixels.width >= 1, pixels.height >= 1, let cropped = cg.cropping(to: pixels) else { throw OiServiceError.invalidInput }
            edited = UIImage(cgImage: cropped)
        case .rotateLeft:
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let size = CGSize(width: cg.height, height: cg.width)
            edited = UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.rotate(by: -.pi / 2)
                image.draw(in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            }
        }
        guard let jpeg = edited.jpegData(compressionQuality: 0.85) else { throw OiServiceError.invalidInput }
        return jpeg
    }
}
