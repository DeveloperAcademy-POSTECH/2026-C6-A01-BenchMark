//
//  OiCardPatternTexture.swift
//  OiDonation
//
//  Created by Codex on 11/6/26.
//

import UIKit

/// The Figma textures encode most of their detail in the alpha channel of white
/// pixels. Treating them as faint white overlays loses that detail on light cards.
@MainActor
enum OiCardPatternTexture {
    private static let cache: NSCache<NSNumber, UIImage> = {
        let cache = NSCache<NSNumber, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()

    static func image(for number: Int) -> UIImage? {
        guard (1...8).contains(number) else { return nil }
        let key = NSNumber(value: number)
        if let image = cache.object(forKey: key) { return image }
        guard let source = UIImage(named: "OiCardPattern\(number)")?.cgImage else { return nil }
        let scale = min(1, 512 / Double(max(source.width, source.height)))
        let width = max(1, Int(Double(source.width) * scale))
        let height = max(1, Int(Double(source.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var tones = [UInt8](repeating: 0, count: width * height)
        var histogram = [Int](repeating: 0, count: 256)
        for i in tones.indices {
            let offset = i * 4
            // Premultiplied RGB retains alpha-encoded detail; opaque satin also
            // follows the same path without a separate material special case.
            let tone = (54 * Int(pixels[offset]) + 183 * Int(pixels[offset + 1])
                + 19 * Int(pixels[offset + 2])) / 256
            tones[i] = UInt8(tone)
            histogram[tone] += 1
        }
        func percentile(_ fraction: Double) -> Int {
            let target = max(1, Int(Double(tones.count) * fraction))
            var count = 0
            for tone in histogram.indices {
                count += histogram[tone]
                if count >= target { return tone }
            }
            return 255
        }
        let low = percentile(0.02), high = max(low + 1, percentile(0.98))
        for i in tones.indices {
            let normalized = min(1, max(0, Double(Int(tones[i]) - low) / Double(high - low)))
            let tone = UInt8((36 + normalized * 204).rounded())
            let offset = i * 4
            pixels[offset] = tone; pixels[offset + 1] = tone; pixels[offset + 2] = tone
            pixels[offset + 3] = 255
        }
        guard let rendered = context.makeImage() else { return nil }
        let image = UIImage(cgImage: rendered)
        cache.setObject(image, forKey: key, cost: width * height * 4)
        return image
    }
}
