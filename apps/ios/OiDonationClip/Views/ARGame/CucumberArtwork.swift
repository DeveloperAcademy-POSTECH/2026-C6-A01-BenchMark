// Created by 이돈혁

import ImageIO
import UIKit

@MainActor
enum CucumberArtwork {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 12
        return cache
    }()
    private static let fallback = UIImage(named: "ARGameIntroCucumber").flatMap(normalized)

    static func load(imageURL: URL?) async -> UIImage? {
        guard let imageURL else { return fallback }
        if let cached = cache.object(forKey: imageURL as NSURL) { return cached }
        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 10
        do {
            let data: Data
            if imageURL.isFileURL {
                data = try Data(contentsOf: imageURL)
            } else {
                let (download, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return fallback }
                data = download
            }
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048
                  ] as CFDictionary),
                  let image = normalized(UIImage(cgImage: thumbnail)) else { return fallback }
            cache.setObject(image, forKey: imageURL as NSURL, cost: Int(image.size.width * image.size.height) * 4)
            return image
        } catch {
            // Keep the established local artwork fallback for unavailable remote images.
            return Task.isCancelled ? nil : fallback
        }
    }

    // Trim transparent padding once, before fitting into intro, tray, or AR slots.
    static func normalized(_ image: UIImage) -> UIImage? {
        guard let source = image.cgImage else { return nil }
        let width = source.width
        let height = source.height
        let rowBytes = width * 4
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ), let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * rowBytes + x * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let raster = context.makeImage(),
              let cropped = raster.cropping(to: CGRect(
                x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1
              )) else { return nil }
        return UIImage(cgImage: cropped)
    }
}
