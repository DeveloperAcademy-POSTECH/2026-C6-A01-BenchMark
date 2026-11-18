//
//  validate_portrait_cutout.swift
//  BenchMark
//
//  Created by 이돈혁 on 11/18/26.
//

import Foundation
import CoreGraphics
import CoreImage
import ImageIO

/// Compiled together with the production OiCharacterForegroundMask source on macOS.
@main struct PortraitCutoutValidation {
    struct Failure: Error { let message: String }
    static let width = 256, height = 384

    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw Failure(message: "Expected transparent reference PNG and output directory") }
        let referenceURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let source = CGImageSourceCreateWithURL(referenceURL as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw Failure(message: "Reference PNG is unreadable") }
        let transparent = try bitmap(); transparent.draw(original, in: bounds)
        let opaque = try bitmap(); opaque.setFillColor(CGColor(gray: 1, alpha: 1)); opaque.fill(bounds)
        opaque.draw(original, in: bounds)
        guard let reference = transparent.makeImage(), let white = opaque.makeImage(),
              OiCharacterForegroundMask.hasTransparentBackground(reference),
              !OiCharacterForegroundMask.hasTransparentBackground(white) else { throw Failure(message: "Reference alpha contract failed") }
        let result = try OiCharacterForegroundMask.image(white, context: CIContext(options: [.cacheIntermediates: false]))
        guard result.width == width, result.height == height,
              OiCharacterForegroundMask.hasTransparentBackground(result) else { throw Failure(message: "Native result alpha contract failed") }
        let before = try pixels(reference), after = try pixels(result)
        var background = 0, removed = 0, foreground = 0, preserved = 0, whiteClothing = 0, preservedWhite = 0
        var differences = 0, channels = 0
        for i in stride(from: 0, to: before.count, by: 4) {
            if before[i + 3] == 0 { background += 1; if after[i + 3] < 16 { removed += 1 } }
            if before[i + 3] > 250 {
                foreground += 1; if after[i + 3] > 200 { preserved += 1 }
                if after[i + 3] > 250 {
                    for c in 0..<3 { differences += abs(Int(before[i + c]) - Int(after[i + c])) }; channels += 3
                }
                if min(before[i], before[i + 1], before[i + 2]) > 225 {
                    whiteClothing += 1; if after[i + 3] > 200 { preservedWhite += 1 }
                }
            }
        }
        let backgroundRatio = Double(removed) / Double(max(1, background))
        let foregroundRatio = Double(preserved) / Double(max(1, foreground))
        let whiteRatio = Double(preservedWhite) / Double(max(1, whiteClothing))
        let colorDifference = Double(differences) / Double(max(1, channels))
        print("background removed: \(removed)/\(background) (\(backgroundRatio))")
        print("foreground retained: \(preserved)/\(foreground) (\(foregroundRatio))")
        print("white clothing retained: \(preservedWhite)/\(whiteClothing) (\(whiteRatio))")
        print("mean RGB difference: \(colorDifference)")
        guard backgroundRatio > 0.95, foregroundRatio > 0.95, whiteClothing > 100, whiteRatio > 0.95,
              colorDifference < 4 else { throw Failure(message: "Native foreground quality regression") }
        for (name, image) in [("reference", reference), ("legacy-white", white), ("native-cutout", result)] {
            guard let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name + ".png") as CFURL,
                "public.png" as CFString, 1, nil) else { throw Failure(message: "Cannot create output PNG") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Cannot write output PNG") }
        }
        print("PASS: actual native Vision foreground segmentation")
    }

    static var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
    static func bitmap() throws -> CGContext {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw Failure(message: "Cannot create bitmap") }
        return context
    }
    static func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try bitmap(); context.draw(image, in: bounds)
        guard let data = context.data else { throw Failure(message: "Cannot read bitmap") }
        return Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: width * height * 4), count: width * height * 4))
    }
}
