//
//  OiPortraitMatte.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/15/26.
//

import UIKit

/// Recovers coverage from two renders of the same pose. A black eye is unchanged
/// between renders, whereas a background pixel follows the background color.
enum OiPortraitMatte {
    nonisolated static func image(black: UIImage, white: UIImage) -> UIImage? {
        guard let b = rgba(black), let w = rgba(white), b.width == w.width, b.height == w.height else { return nil }
        let corners = [0, b.width - 1, (b.height - 1) * b.width, b.width * b.height - 1]
        // A long prop can enter one corner. The empty corner changes most
        // between passes; do not mistake an opaque garment for the backdrop.
        let background = corners.max { lhs, rhs in
            func change(_ pixel: Int) -> Double {
                (0..<3).reduce(0) { $0 + linear(w.bytes[pixel * 4 + $1]) - linear(b.bytes[pixel * 4 + $1]) }
            }
            return change(lhs) < change(rhs)
        }!
        let dark = (0..<3).map { linear(b.bytes[background * 4 + $0]) }
        let light = (0..<3).map { linear(w.bytes[background * 4 + $0]) }
        guard zip(dark, light).allSatisfy({ $1 - $0 > 0.5 }) else { return nil }
        var result = [UInt8](repeating: 0, count: b.bytes.count)
        var clearCount = 0, solidCount = 0
        for offset in stride(from: 0, to: result.count, by: 4) {
            let blackRGB = (0..<3).map { linear(b.bytes[offset + $0]) }
            let differences = (0..<3).map {
                (linear(w.bytes[offset + $0]) - blackRGB[$0]) / (light[$0] - dark[$0])
            }.sorted()
            var alpha = min(1, max(0, 1 - differences[1]))
            // Ignore sub-pixel render noise in fully covered/empty regions.
            if alpha < 0.01 { alpha = 0 }
            if alpha > 0.99 { alpha = 1 }
            if alpha == 0 { clearCount += 1; continue }
            if alpha == 1 { solidCount += 1 }
            for channel in 0..<3 {
                let foreground = (blackRGB[channel] - (1 - alpha) * dark[channel]) / alpha
                result[offset + channel] = UInt8((encoded(foreground) * alpha * 255).rounded())
            }
            result[offset + 3] = UInt8((alpha * 255).rounded())
        }
        guard clearCount > b.width * b.height / 100, solidCount > 100,
              let provider = CGDataProvider(data: Data(result) as CFData),
              let image = CGImage(width: b.width, height: b.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: b.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image, scale: black.scale, orientation: .up)
    }

    nonisolated static func hasTransparentBackground(_ image: UIImage) -> Bool {
        guard let rgba = rgba(image) else { return false }
        var clearCount = 0, foregroundCount = 0
        for offset in stride(from: 3, to: rgba.bytes.count, by: 4) {
            if rgba.bytes[offset] == 0 { clearCount += 1 }
            if rgba.bytes[offset] > 200 { foregroundCount += 1 }
        }
        return clearCount > rgba.width * rgba.height / 100 && foregroundCount > 100
    }

    nonisolated private static func linear(_ byte: UInt8) -> Double {
        let value = Double(byte) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    nonisolated private static func encoded(_ linear: Double) -> Double {
        let value = min(1, max(0, linear))
        return value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    nonisolated private static func rgba(_ image: UIImage) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0,
              cg.width <= 4096, cg.height <= 4096,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        return rendered ? (cg.width, cg.height, bytes) : nil
    }
}
